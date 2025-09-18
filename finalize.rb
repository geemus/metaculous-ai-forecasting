#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler'
Bundler.setup

require 'erb'
require 'excon'
require 'fileutils'
require 'formatador'
require 'json'

require './lib/anthropic'
require './lib/metaculus'
require './lib/perplexity'
require './lib/prompts'
require './lib/utility'

Thread.current[:formatador] = Formatador.new
Thread.current[:formatador].instance_variable_set(:@indent, 0)

FORECASTERS = %i[
  anthropic
  anthropic
  perplexity
  perplexity
].freeze

# metaculus test questions: (binary: 578, numeric: 14333, multiple-choice: 22427, discrete: 38880)
post_id = ARGV[0] || raise('post id argument is required')

FileUtils.mkdir_p("./tmp/#{post_id}/consensus") # create cache directory if needed

post_json = cache_read!(post_id, 'post.json')
question = Metaculus::Question.new(data: JSON.parse(post_json))
if question.existing_forecast? && !%w[578 14333 22427 38880].include?(post_id)
  Formatador.display "\n[bold][green]# Skipping: Already Submitted Forecast for #{post_id}[/] "
  exit
end

research_json = cache_read!(post_id, 'research.json')
research = Perplexity::Response.new(data: JSON.parse(research_json))
@research_output = research.formatted_research

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

Formatador.display "\n[bold][green]# Superforecaster: Summarizing Consensus(#{post_id})…[/] "
consensus_json = cache(post_id, 'forecasts/consensus.json') do
  llm = Anthropic.new
  consensus_prompt = prompt_with_type(llm, question, FORECAST_CONSENSUS_PROMPT_TEMPLATE)
  consensus = llm.eval({ 'role': 'user', 'content': consensus_prompt })
  puts consensus.content
  consensus.to_json
end
consensus = Anthropic::Response.new(data: JSON.parse(consensus_json))

question.submit(consensus)
