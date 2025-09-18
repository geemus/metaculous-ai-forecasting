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

FileUtils.mkdir_p("./tmp/#{post_id}") # create cache directory if needed
FileUtils.mkdir_p("./tmp/#{post_id}/forecasts") # create cache directory if needed

Formatador.display "\n[bold][green]# Metaculus: Loading Cached Post(#{post_id})[/] "
post_json = cache_read!(post_id, 'post.json')
question = Metaculus::Question.new(data: JSON.parse(post_json))
if question.existing_forecast? && !%w[578 14333 22427 38880].include?(post_id)
  Formatador.display "\n[bold][green]# Skipping: Already Submitted Forecast for #{post_id}[/] "
  exit
end

@forecast_prompt = FORECAST_PROMPT_TEMPLATE.result(binding)
puts @forecast_prompt

Formatador.display "\n[bold][green]# Researcher: Loading Cached Research(#{post_id})[/] "
research_json = cache_read!(post_id, 'research.json')
research = Perplexity::Response.new(data: JSON.parse(research_json))
@research_output = research.formatted_research
puts @research_output

BINARY_FORECAST_PROMPT = <<~BINARY_FORECAST_PROMPT
  - At the end of your forecast provide a probabilistic prediction.

  Your prediction should be in this format:
  <probability>
  X%
  </probability>
BINARY_FORECAST_PROMPT

NUMERIC_FORECAST_PROMPT = <<~NUMERIC_FORECAST_PROMPT
  - At the end of your forecast provide percentile predictions of values in the given units and range, only include the values and units, do not use ranges of values.

  Your predictions should be in this format:
  <percentiles>
  Percentile  5: A {unit}
  Percentile 10: B {unit}
  Percentile 20: C {unit}
  Percentile 30: D {unit}
  Percentile 40: E {unit}
  Percentile 50: F {unit}
  Percentile 60: G {unit}
  Percentile 70: H {unit}
  Percentile 80: I {unit}
  Percentile 90: J {unit}
  Percentile 95: K {unit}
  </percentiles>
NUMERIC_FORECAST_PROMPT

MULTIPLE_CHOICE_FORECAST_PROMPT = <<~MULTIPLE_CHOICE_FORECAST_PROMPT
  - At the end of your forecast provide your probabilistic predictions for each option, only include the probability itself.

  Your predictions should be in this format:
  <probabilities>
  Option "A": A%
  Option "B": B%
  ...
  Option "N": N%
  </probabilities>
MULTIPLE_CHOICE_FORECAST_PROMPT

def prompt_with_type(llm, question, prompt_template)
  prompt = prompt_template.result(binding)
  prompt += case question.type
            when 'binary'
              BINARY_FORECAST_PROMPT
            when 'discrete', 'numeric'
              NUMERIC_FORECAST_PROMPT
            when 'multiple_choice'
              MULTIPLE_CHOICE_FORECAST_PROMPT
            else
              raise "Missing template for type: #{question.type}"
            end
  prompt
end

consensus_forecast_prompt_template = ERB.new(<<~CONSENSUS_FORECAST_PROMPT_TEMPLATE, trim_mode: '-')
  Review these predictions from other superforecasters.
  <forecasts>
  <%- @revised_forecasts.each do |forecast| -%>
  <forecast>
  <%= forecast.content %>
  </forecast>
  <%- end -%>
  </forecasts>

  - Summarize the consensus as a final forecast.
  - Before summarizing the consensus, show step-by-step reasoning in clear, logical order starting with <think> on the line before and ending with </think> on the line after.

CONSENSUS_FORECAST_PROMPT_TEMPLATE

@revised_forecasts = []
FORECASTERS.each_with_index do |provider, index|
  Formatador.display "\n[bold][green]# Superforecaster[#{index}: #{provider}]: Loading Cached Revised Forecast(#{post_id})[/] "
  forecast_json = cache_read!(post_id, "forecasts/revision.#{index}.json")
  @revised_forecasts << case provider
                        when :anthropic
                          Anthropic::Response.new(data: JSON.parse(forecast_json))
                        when :perplexity
                          Perplexity::Response.new(data: JSON.parse(forecast_json))
                        end
end

Formatador.display "\n[bold][green]# Superforecaster: Summarizing Consensus…[/] "
consensus_json = cache(post_id, 'forecasts/consensus.json') do
  llm = Anthropic.new
  consensus_prompt = prompt_with_type(llm, question, consensus_forecast_prompt_template)
  consensus = llm.eval({ 'role': 'user', 'content': consensus_prompt })
  consensus.to_json
end
consensus = Anthropic::Response.new(data: JSON.parse(consensus_json))
puts consensus.content

Formatador.display_line "\n[bold][green]## Post Prep:[/]"
question.submit(consensus)
