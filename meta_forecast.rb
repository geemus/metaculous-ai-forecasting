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

@forecast_prompt = cache_read!(post_id, 'prompts/forecast.0.md')

META_FORECAST_TEMPLATE = ERB.new(<<~META_FORECAST_TEMPLATE, trim_mode: '-')
  Review the following responses in the context of the provided system and assistant prompts:

  # System Prompt
  <system-prompt>
  <%= SUPERFORECASTER_SYSTEM_PROMPT %>
  </system-prompt>

  # Assistant Prompt
  <assistant-prompt>
  <%= @forecast_prompt %>
  </assistant-prompt>

  # Responses
  <responses>
  <%- @forecasts.each do |forecast| -%>
  <response>
  <%= forecast.content %>
  </response>
  <%- end -%>
  </responses>

  # Instructions
  - Your goal is to ensure future prompts elicit more accurate and relevant responses.
  - Identify weaknesses in the responses and suggest concrete improvements to the provided system and assistant prompt that would prevent these issues.
  - Structure your feedback as a numbered list and explain the reasoning behind each suggestion.
  - Reference best practices in prompt engineering where relevant.
META_FORECAST_TEMPLATE

Formatador.display "\n[bold][green]# Forecaster: Reviewing Forecasts…[/] "
meta_forecast_json = cache(post_id, 'meta_forecast.json') do
  # perplexity = Perplexity.new(model: 'sonar-deep-research')
  perplexity = Perplexity.new(
    model: 'sonar-pro',
    system: PROMPT_ENGINEER_SYSTEM_PROMPT
  )
  @meta_forecast_prompt = META_FORECAST_TEMPLATE.result(binding)
  cache_write(post_id, 'messages/meta_forecast_input.md', @meta_forecast_prompt)
  meta_forecast = perplexity.eval({ 'role': 'user', 'content': @meta_forecast_prompt })
  cache_write(post_id, 'messages/meta_forecast_output.md', meta_forecast.content)
  meta_forecast.to_json
end
meta_forecast = Perplexity::Response.new(data: JSON.parse(meta_forecast_json))
puts meta_forecast.content
