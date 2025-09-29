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
forecaster_index = ARGV[1]&.to_i || raise('forecaster index argv[1] is required')
init_cache(post_id)

post_json = Metaculus.get_post(post_id).to_json
cache_write(post_id, 'post.json', post_json)
question = Metaculus::Question.new(data: JSON.parse(post_json))
if question.existing_forecast? && !%w[578 14333 22427 38880].include?(post_id)
  Formatador.display "\n[bold][green]# Skipping: Already Submitted Forecast for #{post_id}[/] "
  exit
end

research_json = cache_read!(post_id, 'research.json')
research = Perplexity::Response.new(data: JSON.parse(research_json))
@research_output = research.stripped_content('reflect')

@forecasts = []
FORECASTERS.each_with_index do |provider, index|
  forecast_json = cache_read!(post_id, "forecasts/forecast.#{index}.json")
  @forecasts << case provider
                when :anthropic
                  Anthropic::Response.new(data: JSON.parse(forecast_json))
                when :perplexity
                  Perplexity::Response.new(data: JSON.parse(forecast_json))
                end
end

provider = FORECASTERS[forecaster_index]
@forecast = @forecasts[forecaster_index]

Formatador.display "\n[bold][green]# Superforecaster[#{forecaster_index}: #{provider}]: Revising Forecast(#{post_id})…[/] "
cache(post_id, "forecasts/revision.#{forecaster_index}.json") do
  llm = case provider
        when :anthropic
          Anthropic.new(temperature: 0.1)
        when :perplexity
          Perplexity.new(
            system: SUPERFORECASTER_SYSTEM_PROMPT,
            temperature: 0.1
          )
        end
  forecast_prompt = prompt_with_type(llm, question, SHARED_FORECAST_PROMPT_TEMPLATE)
  forecast_delphi_prompt = prompt_with_type(llm, question, FORECAST_DELPHI_PROMPT_TEMPLATE)
  cache_write(post_id, "inputs/revision.#{forecaster_index}.md", forecast_delphi_prompt)
  revision = llm.eval(
    { 'role': 'user', 'content': forecast_prompt },
    { 'role': 'assistant', 'content': @forecast.content },
    { 'role': 'user', 'content': forecast_delphi_prompt }
  )
  puts revision.content
  cache_write(post_id, "outputs/revision.#{forecaster_index}.md", revision.content)
  cache_concat(post_id, 'reflects.md',
               "# Revision {#{forecaster_index}: #{provider}}\n#{revision.extracted_content('reflect')}\n\n")
  revision.to_json
end
