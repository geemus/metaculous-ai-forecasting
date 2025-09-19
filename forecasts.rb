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

Formatador.display "\n[bold][green]# Metaculus: Getting Post(#{post_id})…[/] "
post_json = cache(post_id, 'post.json') do
  Metaculus.get_post(post_id).to_json
end
question = Metaculus::Question.new(data: JSON.parse(post_json))

if question.existing_forecast? && !%w[578 14333 22427 38880].include?(post_id)
  Formatador.display "\n[bold][green]# Skipping: Already Submitted Forecast for #{post_id}[/] "
  exit
end

@forecast_prompt = FORECAST_PROMPT_TEMPLATE.result(binding)
puts @forecast_prompt

Formatador.display "\n[bold][green]# Researcher: Loading Cached Research[/] "
research_json = cache_read!(post_id, 'research.json')
research = Perplexity::Response.new(data: JSON.parse(research_json))
@research_output = research.formatted_research
puts @research_output

@forecasts = []
FORECASTERS.each_with_index do |provider, index|
  Formatador.display "\n[bold][green]# Superforecaster[#{index}: #{provider}]: Forecasting…[/] "
  forecast_json = cache(post_id, "forecasts/forecast.#{index}.json") do
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
    forecast.to_json
  end
  @forecasts << case provider
                when :anthropic
                  Anthropic::Response.new(data: JSON.parse(forecast_json))
                when :perplexity
                  Perplexity::Response.new(data: JSON.parse(forecast_json))
                end
end

@revised_forecasts = []
Formatador.display_line "\n[bold][green]# Meta: Optimizing Forecasts[/] "
FORECASTERS.each_with_index do |provider, index|
  @forecast = @forecasts[index]

  forecast_revision_json = cache(post_id, "forecasts/revision.#{index}.json") do
    Formatador.display "\n[bold][green]## Superforecaster[#{index}: #{provider}]: Revising Forecast…[/] "
    llm = case provider
          when :anthropic
            Anthropic.new
          when :perplexity
            Perplexity.new(system: SUPERFORECASTER_SYSTEM_PROMPT)
          end
    forecast_prompt = prompt_with_type(llm, question, SHARED_FORECAST_PROMPT_TEMPLATE)
    forecast_delphi_prompt = prompt_with_type(llm, question, FORECAST_DELPHI_PROMPT_TEMPLATE)
    revision = llm.eval(
      { 'role': 'user', 'content': forecast_prompt },
      { 'role': 'assistant', 'content': @forecast.content },
      { 'role': 'user', 'content': forecast_delphi_prompt }
    )
    puts revision.content
    revision.to_json
  end
  @revised_forecasts << case provider
                        when :anthropic
                          Anthropic::Response.new(data: JSON.parse(forecast_revision_json))
                        when :perplexity
                          Perplexity::Response.new(data: JSON.parse(forecast_revision_json))
                        end
end

Formatador.display "\n[bold][green]# Superforecaster: Summarizing Consensus…[/] "
consensus_json = cache(post_id, 'forecasts/consensus.json') do
  llm = Anthropic.new
  consensus_prompt = prompt_with_type(llm, question, FORECAST_CONSENSUS_PROMPT_TEMPLATE)
  consensus = llm.eval({ 'role': 'user', 'content': consensus_prompt })
  consensus.to_json
end
consensus = Anthropic::Response.new(data: JSON.parse(consensus_json))
puts consensus.content

Formatador.display_line "\n[bold][green]## Post Prep:[/]"
question.submit(consensus)
