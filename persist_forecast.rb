#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/script_helpers'

post_id = ARGV[0] || raise('post id argv[0] is required')

if TestQuestions.test_question?(post_id)
  puts "Skipping test question: #{post_id}"
  exit
end

data_path = "data/unresolved/#{post_id}.json"
if File.exist?(data_path)
  puts "Skipping: #{data_path} already exists"
  exit
end

question = fetch_question(post_id)
initial_forecasts = load_forecasts(post_id, type: 'forecast')
revised_forecasts = load_forecasts(post_id, type: 'revision')
consensus_json = cache_read!(post_id, 'forecasts/consensus.json')
consensus = Response.new(:anthropic, json: consensus_json)

def forecast_entry(question, response)
  entry = { provider: response.provider.to_s, model: response.model }
  case question.type
  when 'binary'
    entry.merge(probability: response.probability)
  when 'numeric', 'discrete'
    entry.merge(percentiles: response.percentiles)
  when 'multiple_choice'
    entry.merge(probabilities: response.probabilities)
  end
end

def consensus_forecast(question, consensus)
  case question.type
  when 'binary'
    { probability: consensus.probability }
  when 'numeric', 'discrete'
    { percentiles: consensus.percentiles }
  when 'multiple_choice'
    { probabilities: consensus.probabilities }
  end
end

def community_prediction(question)
  latest = question.data.dig('question', 'aggregations', 'recency_weighted', 'latest')
  return nil unless latest

  case question.type
  when 'binary'
    { probability: latest['centers']&.first }
  when 'numeric', 'discrete'
    { median: latest['centers']&.first }
  when 'multiple_choice'
    options = question.options || []
    centers = latest['centers'] || []
    options.each_with_index.to_h { |opt, i| [opt, centers[i]] }
  end
end

def tournament_ids(question)
  projects = question.data['projects'] || {}
  projects.values.flatten.filter_map do |proj|
    proj['slug'] if proj.is_a?(Hash) && proj['type'] == 'tournament' && proj['slug']
  end
end

record = {
  post_id: question.post_id,
  tournament_ids: tournament_ids(question),
  title: question.title,
  question_type: question.type,
  tags: question.data['tags'] || [],
  forecasted_at: Time.now.utc.iso8601,
  scheduled_resolve_time: question.data['scheduled_resolve_time'],
  community_prediction_at_forecast: community_prediction(question),
  consensus_forecast: consensus_forecast(question, consensus),
  individual_forecasts: {
    initial: initial_forecasts.map { |f| forecast_entry(question, f) },
    revised: revised_forecasts.map { |f| forecast_entry(question, f) }
  }
}

FileUtils.mkdir_p('data/unresolved')
File.write(data_path, JSON.pretty_generate(record))
puts "Persisted: #{data_path}"
