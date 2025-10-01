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
  puts format(
    '%<type>s[%<index>i: %<provider>s]: %<probability>s @ $%<cost>0.2f',
    type: type,
    index: forecaster_index,
    provider: provider,
    probability: @forecast.probability.round(10).to_s,
    cost: @forecast.cost
  )
  puts "#{type}[#{forecaster_index}: #{provider}]: #{@forecast.probability.round(10)}"
when 'discrete', 'numeric'
  puts format(
    '%<type>s[%<index>i: %<provider>s]: %<percentiles>s @ $%<cost>0.2f',
    type: type,
    index: forecaster_index,
    provider: provider,
    percentiles: @forecast.percentiles.to_s,
    cost: @forecast.cost
  )
when 'multiple_choice'
  puts format(
    '%<type>s[%<index>i: %<provider>s]: %<probabilities>s @ $%<cost>0.2f',
    type: type,
    index: forecaster_index,
    provider: provider,
    probabilitie: @forecast.probabilities.to_s,
    cost: @forecast.cost
  )
end
