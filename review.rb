#!/usr/bin/env ruby
# frozen_string_literal: true

require 'set'
require_relative 'lib/script_helpers'

TOURNAMENTS = %w[fall-aib-2025 minibench spring-aib-2026].freeze
DATA_FILE = 'data/resolved.jsonl'

def my_forecast_value(question)
  latest = question.data.dig('question', 'my_forecasts', 'latest')
  return nil unless latest

  case question.type
  when 'binary'
    latest['probability_yes']
  when 'multiple_choice'
    latest['probability_yes_per_category']
  when 'numeric', 'discrete'
    latest['continuous_cdf']
  end
end

def community_prediction_value(question)
  agg = question.data.dig('question', 'aggregations', 'recency_weighted', 'latest')
  return nil unless agg

  case question.type
  when 'binary'
    agg['centers']&.first
  when 'multiple_choice'
    options = question.options
    centers = agg['centers']
    return nil unless options && centers

    options.each_with_index.each_with_object({}) do |(option, i), hash|
      hash[option] = centers[i]
    end
  when 'numeric', 'discrete'
    agg['centers']&.first
  end
end

def brier_score(question_type, forecast, resolution)
  return nil if forecast.nil? || resolution.nil?

  case question_type
  when 'binary'
    r = case resolution.to_s.downcase
        when 'yes', '1', '1.0', 'true' then 1.0
        when 'no', '0', '0.0', 'false' then 0.0
        else resolution.to_f
        end
    (forecast.to_f - r)**2
  when 'multiple_choice'
    return nil unless forecast.is_a?(Hash)

    n = forecast.length
    return nil if n.zero?

    sum = forecast.sum do |option, prob|
      r = (option.to_s == resolution.to_s) ? 1.0 : 0.0
      (prob.to_f - r)**2
    end
    sum / n
  end
  # Numeric/discrete Brier score requires CDF-based calculation; omitted here
end

def load_per_forecaster_data(post_id, question_type)
  Provider::FORECASTERS.each_with_index.each_with_object({}) do |(provider, index), hash|
    forecast_json = begin
      cache_read!(post_id, "forecasts/forecast.#{index}.json")
    rescue RuntimeError
      nil
    end
    revision_json = begin
      cache_read!(post_id, "forecasts/revision.#{index}.json")
    rescue RuntimeError
      nil
    end

    next unless forecast_json || revision_json

    entry = {}
    if forecast_json
      r = Response.new(provider, json: forecast_json)
      entry['forecast'] = extract_forecast_value(r, question_type)
    end
    if revision_json
      r = Response.new(provider, json: revision_json)
      entry['revision'] = extract_forecast_value(r, question_type)
    end
    hash[provider.to_s] = entry.compact
  end.reject { |_, v| v.empty? }
end

def extract_forecast_value(response, question_type)
  case question_type
  when 'binary'
    response.probability
  when 'numeric', 'discrete'
    response.percentiles
  when 'multiple_choice'
    response.probabilities
  end
rescue StandardError
  nil
end

def tags_from_data(data)
  projects = data['projects'] || []
  projects.filter_map do |project|
    project['name'] if project['type'] != 'tournament'
  end
end

def build_record(question)
  post_id = question.post_id
  resolution = question.data.dig('question', 'resolution')
  forecast = my_forecast_value(question)
  community = community_prediction_value(question)
  score = brier_score(question.type, forecast, resolution)
  per_forecaster = load_per_forecaster_data(post_id, question.type)

  record = {
    'post_id' => post_id,
    'title' => question.title,
    'question_type' => question.type,
    'tags' => tags_from_data(question.data),
    'resolved_at' => question.data.dig('question', 'actual_resolve_time') ||
                     question.data.dig('question', 'scheduled_resolve_time'),
    'resolution' => resolution,
    'our_forecast' => forecast,
    'community_prediction' => community,
    'brier_score' => score,
    'recorded_at' => Time.now.utc.iso8601
  }
  record['per_forecaster'] = per_forecaster unless per_forecaster.empty?
  record
end

# Load existing resolved post IDs to avoid duplicates
existing_ids = Set.new
if File.exist?(DATA_FILE)
  File.readlines(DATA_FILE, chomp: true).each do |line|
    next if line.strip.empty?

    record = JSON.parse(line)
    existing_ids << record['post_id']
  end
end

new_records = []

TOURNAMENTS.each do |tournament_id|
  Formatador.display "\n[bold][green]# Review: Fetching resolved questions for #{tournament_id}…[/] "
  questions = Metaculus.list_resolved_tournament_questions(tournament_id)
  puts " found #{questions.length} resolved questions"

  questions.each do |question|
    post_id = question.post_id
    if existing_ids.include?(post_id)
      puts "  Skipping #{post_id} (already recorded)"
      next
    end

    puts "  Recording #{post_id}: #{question.title}"
    record = build_record(question)
    new_records << record
    existing_ids << post_id
  end
end

if new_records.empty?
  puts 'No new resolved questions to record.'
  exit 0
end

FileUtils.mkdir_p('data')
File.open(DATA_FILE, 'a') do |f|
  new_records.each do |record|
    f.puts record.to_json
  end
end

puts "Added #{new_records.count} new resolved question record(s)."
