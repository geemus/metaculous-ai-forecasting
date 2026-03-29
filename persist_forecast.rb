#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/script_helpers'

post_id = ARGV[0] || raise('post id argument is required')

if TestQuestions.test_question?(post_id)
  Formatador.display_line "\n[bold][yellow]# Persist: Skipping test question #{post_id}[/]"
  exit
end

question = fetch_question(post_id)

tournament_id = question.data.dig('projects', 'default_project', 'slug') ||
                raise("Cannot determine tournament_id for post #{post_id}")

output_path = "data/unresolved/#{tournament_id}/#{post_id}.json"

if File.exist?(output_path)
  Formatador.display_line "\n[bold][yellow]# Persist: Already exists, skipping #{output_path}[/]"
  exit
end

Formatador.display "\n[bold][green]# Persist: Writing forecast record for #{post_id}…[/] "

def forecast_value(response, question_type)
  case question_type
  when 'binary'
    { probability: response.probability }
  when 'numeric', 'discrete'
    { percentiles: response.percentiles }
  when 'multiple_choice'
    { probabilities: response.probabilities }
  else
    {}
  end
end

forecasters = Provider::FORECASTERS
initial_forecasts = load_forecasts(post_id, type: 'forecast')
revised_forecasts = load_forecasts(post_id, type: 'revision')

consensus_json = cache_read!(post_id, 'forecasts/consensus.json')
consensus = Response.new(:anthropic, json: consensus_json)

community = question.data.dig('question', 'aggregations', 'recency_weighted', 'latest')
scheduled_resolve_time = question.data.dig('question', 'scheduled_resolve_time')

record = {
  post_id: question.post_id,
  tournament_id: tournament_id,
  title: question.title,
  question_type: question.type,
  tags: (question.data['tags'] || []).map { |t| t.is_a?(Hash) ? t['name'] : t },
  forecasted_at: Time.now.utc.iso8601,
  scheduled_resolve_time: scheduled_resolve_time,
  community_prediction_at_forecast: community,
  consensus_forecast: forecast_value(consensus, question.type),
  individual_forecasts: {
    initial: initial_forecasts.each_with_index.map do |f, i|
      { provider: forecasters[i].to_s }.merge(forecast_value(f, question.type))
    end,
    revised: revised_forecasts.each_with_index.map do |f, i|
      { provider: forecasters[i].to_s }.merge(forecast_value(f, question.type))
    end
  }
}

FileUtils.mkdir_p(File.dirname(output_path))
File.write(output_path, JSON.pretty_generate(record))
Formatador.display_line "done."
