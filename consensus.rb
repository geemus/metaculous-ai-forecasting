#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler'
Bundler.setup

require 'erb'
require 'excon'
require 'fileutils'
require 'json'

require './lib/anthropic'
require './lib/deepseek'
require './lib/metaculus'
require './lib/perplexity'
require './lib/prompts'
require './lib/utility'

FORECASTERS = %i[
  anthropic
  anthropic
  perplexity
  perplexity
  deepseek
  deepseek
].freeze

# metaculus test questions: (binary: 578, numeric: 14333, multiple-choice: 22427, discrete: 38880)
post_id = ARGV[0] || raise('post id argument is required')
init_cache(post_id)

post_json = Metaculus.get_post(post_id).to_json
cache_write(post_id, 'post.json', post_json)
question = Metaculus::Question.new(data: JSON.parse(post_json))
if question.existing_forecast? && !%w[578 14333 22427 38880].include?(post_id)
  Formatador.display "\n[bold][green]# Skipping: Already Submitted Forecast for #{post_id}[/] "
  exit
end

research_json = cache_read!(post_id, 'research.json')
research = Perplexity::Response.new(json: research_json)
@research_output = research.stripped_content('reflect')

@revised_forecasts = []
FORECASTERS.each_with_index do |provider, index|
  forecast_json = cache_read!(post_id, "forecasts/revision.#{index}.json")
  @revised_forecasts << case provider
                        when :anthropic
                          Anthropic::Response.new(json: forecast_json)
                        when :deepseek
                          DeepSeek::Response.new(json: forecast_json)
                        when :perplexity
                          Perplexity::Response.new(json: forecast_json)
                        end
end

Formatador.display "\n[bold][green]# Superforecaster: Summarizing Consensus(#{post_id})…[/] "
consensus_json = cache(post_id, 'forecasts/consensus.json') do
  llm = Anthropic.new
  consensus_prompt = prompt_with_type(llm, question, FORECAST_CONSENSUS_PROMPT_TEMPLATE)
  cache_write(post_id, 'inputs/consensus.md', consensus_prompt)
  consensus = llm.eval({ 'role': 'user', 'content': consensus_prompt })
  cache_write(post_id, 'outputs/consensus.md', consensus.content)
  cache_concat(post_id, 'reflects.md', "# Consensus\n#{consensus.extracted_content('reflect')}")
  consensus.to_json
end
consensus = Anthropic::Response.new(json: consensus_json)
puts consensus.content

question.submit(consensus)
