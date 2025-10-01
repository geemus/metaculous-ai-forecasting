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
  anthropic
  perplexity
  perplexity
  deepseek
  deepseek
].freeze

# metaculus test questions: (binary: 578, numeric: 14333, multiple-choice: 22427, discrete: 38880)
post_id = ARGV[0] || raise('post id argv[0] is required')
forecaster_index = ARGV[1].to_i || raise('forecaster_index argv[1] is required')
type = ARGV[2] || raise('type argv[2] is required')
init_cache(post_id)

post_json = cache_read!(post_id, 'post.json')
question = Metaculus::Question.new(data: JSON.parse(post_json))
if question.existing_forecast? && !%w[578 14333 22427 38880].include?(post_id)
  Formatador.display "\n[bold][green]# Skipping: Already Submitted Forecast for #{post_id}[/] "
  exit
end

forecast_json = cache_read!(post_id, "forecasts/#{type}.#{forecaster_index}.json")
provider = FORECASTERS[forecaster_index]
@forecast = case provider
            when :anthropic
              Anthropic::Response.new(json: forecast_json)
            when :deepseek
              DeepSeek::Response.new(json: forecast_json)
            when :perplexity
              Perplexity::Response.new(json: forecast_json)
            end

case question.type
when 'binary'
  puts "#{type}[#{forecaster_index}: #{provider}]: #{@forecast.probability.round(10)}"
when 'multiple_choice'
  puts "#{type}[#{forecaster_index}: #{provider}]: #{@forecast.probabilities}"
end
