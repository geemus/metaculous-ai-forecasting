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
post_id = ARGV[0] || raise('post id argv[0] is required')
forecaster_index = ARGV[1]&.to_i || raise('forecaster index argv[1] is required')

FileUtils.mkdir_p("./tmp/#{post_id}") # create cache directory if needed
FileUtils.mkdir_p("./tmp/#{post_id}/forecasts") # create cache directory if needed

post_json = cache_read!(post_id, 'post.json')
question = Metaculus::Question.new(data: JSON.parse(post_json))
if question.existing_forecast? && !%w[578 14333 22427 38880].include?(post_id)
  Formatador.display "\n[bold][green]# Skipping: Already Submitted Forecast for #{post_id}[/] "
  exit
end

research_json = cache_read!(post_id, 'research.json')
research = Perplexity::Response.new(data: JSON.parse(research_json))
@research_output = research.formatted_research

provider = FORECASTERS[forecaster_index]
Formatador.display "\n[bold][green]# Superforecaster[#{forecaster_index}: #{provider}]: Forecasting(#{post_id})…[/] "
cache(post_id, "forecasts/forecast.#{forecaster_index}.json") do
  llm = case provider
        when :anthropic
          Anthropic.new(temperature: 0.9) # 0-1
        when :perplexity
          Perplexity.new(
            system: SUPERFORECASTER_SYSTEM_PROMPT,
            temperature: 0.9
          ) # 0-2
        end
  forecast_prompt = prompt_with_type(llm, question, SHARED_FORECAST_PROMPT_TEMPLATE)
  forecast = llm.eval({ 'role': 'user', 'content': forecast_prompt })
  puts forecast.content
  cache_write(post_id, "forecasts/forecast.#{forecaster_index}.md", forecast.content)
  forecast.to_json
end
