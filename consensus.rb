#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler'
Bundler.setup

require 'erb'
require 'excon'
require 'fileutils'
require 'json'

require './lib/anthropic'
require './lib/metaculus'
require './lib/perplexity'
require './lib/prompts'
require './lib/utility'

FORECASTERS = %i[
  anthropic
  anthropic
  perplexity
  perplexity
].freeze

# metaculus test questions: (binary: 578, numeric: 14333, multiple-choice: 22427, discrete: 38880)
post_id = ARGV[0] || raise('post id argument is required')
init_cache(post_id)

post_json = cache_read!(post_id, 'post.json')
question = Metaculus::Question.new(data: JSON.parse(post_json))
if question.existing_forecast? && !%w[578 14333 22427 38880].include?(post_id)
  Formatador.display "\n[bold][green]# Skipping: Already Submitted Forecast for #{post_id}[/] "
  exit
end

research_json = cache_read!(post_id, 'research.json')
research = Perplexity::Response.new(data: JSON.parse(research_json))
@research_output = research.content

@revised_forecasts = []
FORECASTERS.each_with_index do |provider, index|
  forecast_json = cache_read!(post_id, "forecasts/revision.#{index}.json")
  @revised_forecasts << case provider
                        when :anthropic
                          Anthropic::Response.new(data: JSON.parse(forecast_json))
                        when :perplexity
                          Perplexity::Response.new(data: JSON.parse(forecast_json))
                        end
end

case question.type
when 'binary'
  count = @revised_forecasts.count
  values = @revised_forecasts.map(&:probability).map { |p| p.round(10) }
  sorted = values.sort
  mid = (sorted.count - 1) / 2.0
  median = (sorted[mid.floor] + sorted[mid.ceil]) / 2.0
  standard_deviation = stddev(values).round(10)
  Formatador.display "\n[bold][green]## Forecast: #{values}, count: #{count}, median: #{median}, stddev: #{standard_deviation}[/]\n"
when 'multiple_choice'
  count = @revised_forecasts.count
  probabilities = @revised_forecasts.map(&:probabilities)
  probabilities.first.keys.each do |key|
    values = probabilities.map { |forecast_probabilities| forecast_probabilities[key].round(10) }
    sorted = values.sort
    mid = (sorted.count - 1) / 2.0
    median = (sorted[mid.floor] + sorted[mid.ceil]) / 2.0
    standard_deviation = stddev(values).round(10)
    Formatador.display "\n[bold][green]## Forecasts: `#{key}` = #{values}, count: #{count}, median: #{median}, stddev: #{standard_deviation}[/]"
  end
  puts
end

Formatador.display "\n[bold][green]# Superforecaster: Summarizing Consensus(#{post_id})…[/] "
consensus_json = cache(post_id, 'forecasts/consensus.json') do
  llm = Anthropic.new
  consensus_prompt = prompt_with_type(llm, question, FORECAST_CONSENSUS_PROMPT_TEMPLATE)
  cache_write(post_id, 'inputs/consensus.md', consensus_prompt)
  consensus = llm.eval({ 'role': 'user', 'content': consensus_prompt })
  cache_write(post_id, 'outputs/consensus.md', consensus.content)
  consensus.to_json
end
consensus = Anthropic::Response.new(data: JSON.parse(consensus_json))
puts consensus.content

question.submit(consensus)
