#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/script_helpers'

FORECASTERS = Provider::FORECASTERS

post_id = ARGV[0] || raise('post id argv[0] is required')
forecaster_index = ARGV[1].to_i || raise('forecaster_index argv[1] is required')
type = ARGV[2] || raise('type argv[2] is required')

question = load_cached_question(post_id)

forecast_json = cache_read!(post_id, "forecasts/#{type}.#{forecaster_index}.json")
provider = FORECASTERS[forecaster_index]
@forecast = Response.new(provider, json: forecast_json)

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
    probabilities: @forecast.probabilities.to_s,
    cost: @forecast.cost
  )
end
