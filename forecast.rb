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
require './lib/openai'
require './lib/perplexity'
require './lib/prompts'
require './lib/utility'

FORECASTERS = %i[
  anthropic
  perplexity
  deepseek
].freeze

# metaculus test questions: (binary: 578, numeric: 14333, multiple-choice: 22427, discrete: 38880)
post_id = ARGV[0] || raise('post id argv[0] is required')
forecaster_index = ARGV[1]&.to_i || raise('forecaster index argv[1] is required')
init_cache(post_id)

post_json = Metaculus.get_post(post_id).to_json
cache_write(post_id, 'post.json', post_json)
question = Metaculus::Question.new(data: JSON.parse(post_json))
if question.existing_forecast? && !%w[578 14333 22427 38880].include?(post_id)
  Formatador.display "\n[bold][green]# Skipping: Already Submitted Forecast for #{post_id}[/] "
  exit
end

cache_write(post_id, 'inputs/system.superforecaster.md', SUPERFORECASTER_SYSTEM_PROMPT)

research_json = cache_read!(post_id, 'research.json')
research = Perplexity::Response.new(json: research_json)
@research_output = research.stripped_content('reflect')

provider = FORECASTERS[forecaster_index]
Formatador.display "\n[bold][green]# Superforecaster[#{forecaster_index}: #{provider}]: Forecasting(#{post_id})…[/] "
cache(post_id, "forecasts/forecast.#{forecaster_index}.json") do
  llm_args = { system: SUPERFORECASTER_SYSTEM_PROMPT, temperature: 0.9 }
  llm = case provider
        when :anthropic
          Anthropic.new(**llm_args)
        when :deepseek
          DeepSeek.new(**llm_args)
        when :perplexity
          Perplexity.new(**llm_args)
        end
  forecast_prompt = prompt_with_type(llm, question, SHARED_FORECAST_PROMPT_TEMPLATE)
  cache_write(post_id, "inputs/forecast.#{forecaster_index}.md", forecast_prompt)
  forecast = llm.eval({ 'role': 'user', 'content': forecast_prompt })
  puts forecast.content
  cache_write(post_id, "outputs/forecast.#{forecaster_index}.md", forecast.content)
  cache_concat(post_id, 'reflects.md',
               "# Forecast {#{forecaster_index}: #{provider}}\n#{forecast.extracted_content('reflect')}\n\n")
  forecast.to_json
end
