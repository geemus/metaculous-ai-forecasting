#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/script_helpers'

UNRESOLVED_DIR = 'data/unresolved'
RESOLVED_DIR = 'data/resolved'

unless Dir.exist?(UNRESOLVED_DIR)
  puts 'No data/unresolved directory, nothing to do'
  exit
end

def brier_score(forecast_data, resolved_question)
  case forecast_data['question_type']
  when 'binary'
    probability = forecast_data.dig('consensus_forecast', 'probability')
    return nil if probability.nil?

    outcome = resolved_question.resolution == 'yes' ? 1.0 : 0.0
    (probability - outcome)**2
  when 'multiple_choice'
    probs = forecast_data.dig('consensus_forecast', 'probabilities')
    return nil if probs.nil?

    resolution = resolved_question.resolution
    probs.sum { |option, p| ((option == resolution ? 1.0 : 0.0) - p)**2 }
  end
end

now = Time.now.utc
changed = false

Dir.each_child(UNRESOLVED_DIR) do |tournament_id|
  tournament_dir = "#{UNRESOLVED_DIR}/#{tournament_id}"
  next unless File.directory?(tournament_dir)

  pending = Dir.glob("#{tournament_dir}/*.json").map do |path|
    data = JSON.parse(File.read(path))
    { path: path, post_id: data['post_id'].to_s, data: data }
  end

  due = pending.select do |record|
    scheduled = record[:data]['scheduled_resolve_time']
    next false if scheduled.nil?

    Time.parse(scheduled) <= now
  end

  if due.empty?
    puts "#{tournament_id}: no due questions, skipping API call"
    next
  end

  puts "#{tournament_id}: checking #{due.size} due question(s)…"

  resolved_questions = Metaculus.list_resolved_tournament_questions(tournament_id)
  resolved_by_id = resolved_questions.each_with_object({}) { |q, h| h[q.post_id.to_s] = q }

  due.each do |record|
    post_id = record[:post_id]
    resolved_question = resolved_by_id[post_id]
    next unless resolved_question

    puts "  resolving #{post_id}: #{resolved_question.title}"

    resolved_record = record[:data].merge(
      'resolved_at' => resolved_question.resolve_time,
      'resolution' => resolved_question.resolution,
      'community_prediction_at_close' => resolved_question.data.dig(
        'question', 'aggregations', 'recency_weighted', 'latest'
      ),
      'brier_score' => brier_score(record[:data], resolved_question)
    )

    resolved_path = "#{RESOLVED_DIR}/#{tournament_id}/#{post_id}.json"
    FileUtils.mkdir_p(File.dirname(resolved_path))
    File.write(resolved_path, JSON.pretty_generate(resolved_record))
    File.delete(record[:path])

    changed = true
  end
end

puts changed ? 'Resolutions recorded.' : 'No resolutions found.'
