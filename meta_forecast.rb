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

post_json = cache_read!(post_id, 'post.json')
question = Metaculus::Question.new(data: JSON.parse(post_json))
if question.existing_forecast? && !%w[578 14333 22427 38880].include?(post_id)
  Formatador.display "\n[bold][green]# Skipping: Already Submitted Forecast for #{post_id}[/] "
  exit
end

system "./forecast.rb #{post_id} #{forecaster_index}"
puts
forecast_json = cache_read!(post_id, "forecasts/forecast.#{forecaster_index}.json")
@forecast = case FORECASTERS[forecaster_index]
            when :anthropic
              Anthropic::Response.new(data: JSON.parse(forecast_json))
            when :perplexity
              Perplexity::Response.new(data: JSON.parse(forecast_json))
            end

@forecast_prompt = cache_read!(post_id, "prompts/forecast.#{forecaster_index}.md")

META_FORECAST_TEMPLATE = ERB.new(<<~META_FORECAST_TEMPLATE, trim_mode: '-')
  Review the following system prompt, assistant prompt, and responses:

  # System Prompt
  <system-prompt>
  <%= SUPERFORECASTER_SYSTEM_PROMPT %>
  </system-prompt>

  # Assistant Prompt
  <assistant-prompt>
  <%= @forecast_prompt %>
  </assistant-prompt>

  # Responses
  <response>
  <%= @forecast.content %>
  </response>
META_FORECAST_TEMPLATE

Formatador.display "\n[bold][green]# Forecaster: Reviewing Forecasts…[/] "
meta_forecast_json = cache(post_id, "meta_forecast.#{forecaster_index}.json") do
  # perplexity = Perplexity.new(model: 'sonar-deep-research')
  perplexity = Perplexity.new(
    model: 'sonar-pro',
    system: PROMPT_ENGINEER_SYSTEM_PROMPT
  )
  @meta_forecast_prompt = META_FORECAST_TEMPLATE.result(binding)
  cache_write(post_id, "messages/meta_forecast_input.#{forecaster_index}.md", @meta_forecast_prompt)
  meta_forecast = perplexity.eval({ 'role': 'user', 'content': @meta_forecast_prompt })
  cache_write(post_id, "messages/meta_forecast_output.#{forecaster_index}.md", meta_forecast.content)
  meta_forecast.to_json
end
meta_forecast = Perplexity::Response.new(data: JSON.parse(meta_forecast_json))
puts meta_forecast.content
