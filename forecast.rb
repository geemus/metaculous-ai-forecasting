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

Formatador.display "\n[bold][green]# Metaculus: Getting Post(#{post_id})…[/] "
post_json = cache(post_id, 'post.json') do
  Metaculus.get_post(post_id).to_json
end
question = Metaculus::Question.new(data: JSON.parse(post_json))

@forecast_prompt = ERB.new(<<~FORECAST_PROMPT_TEMPLATE, trim_mode: '-').result(binding)
  Forecast Question:
  <question>
  <%= question.title %>
  </question>
  <%- if question.options && !question.options.empty? -%>
  <options>
  <%= question.options %>
  </options>
  <%- end -%>

  Forecast Background:
  <background>
  <%= question.background %>
  </background>
  <%- unless question.metadata_content.empty? -%>

  Question Metadata:
  <metadata>
  <%= question.metadata_content %>
  </metadata>
  <%- end -%>

  Criteria for determining forecast outcome, which have not yet been met:
  <criteria>
  <%= question.criteria_content %>
  </criteria>

  Existing Metaculus Forecasts Aggregate:
  <aggregate>
  <%= question.aggregate_content %>
  </aggregate>
FORECAST_PROMPT_TEMPLATE
puts @forecast_prompt

@research_prompt = @forecast_prompt
Formatador.display "\n[bold][green]# Researcher: Drafting Research…[/] "
research_json = cache(post_id, 'research.0.json') do
  perplexity = Perplexity.new(model: 'sonar-deep-research')
  research = perplexity.eval({ 'role': 'user', 'content': research_prompt })
  research.to_json
end
research = Perplexity::Response.new(data: JSON.parse(research_json))
@research_output = research.formatted_research
puts @research_output

shared_forecast_prompt_template = ERB.new(<<~SHARED_FORECAST_PROMPT_TEMPLATE, trim_mode: '-')
  Create a forecast based on the following information.

  <%= @forecast_prompt -%>

  Here is a summary of relevant data from your research assistant:
  <research>
  <%= @research_output -%>
  </research>

  1. Today is <%= Time.now.strftime('%B %d, %Y') %>. Consider the time remaining before the outcome of the question will become known.
  <%- unless %w[sonar-reasoning sonar-reasoning-pro sonar-deep-research].include?(llm.model) -%>
  2. Before providing your forecast, show step-by-step reasoning in clear, logical order starting with <reasoning> on the line before and ending with </reasoning> on the line after.
  <%- end -%>

SHARED_FORECAST_PROMPT_TEMPLATE

BINARY_FORECAST_PROMPT = <<~BINARY_FORECAST_PROMPT
  - At the end of your forecast provide a probabilistic prediction.

  Your response should be in this format:
  <forecast>
  {forecast}

  <probability>
  X%
  </probability>
  </forecast>
BINARY_FORECAST_PROMPT

NUMERIC_FORECAST_PROMPT = <<~NUMERIC_FORECAST_PROMPT
  - At the end of your forecast provide percentile predictions of values in the given units and range, only include the values and units, do not use ranges of values.

  After reasoning, your response should be in this format:
  <forecast>
  {forecast}

  <percentiles>
  Percentile A: A {unit}
  Percentile B: B {unit}
  ...
  Percentile N: N {unit}
  </percentiles>
  </forecast>
NUMERIC_FORECAST_PROMPT

MULTIPLE_CHOICE_FORECAST_PROMPT = <<~MULTIPLE_CHOICE_FORECAST_PROMPT
  - At the end of your forecast provide your probabilistic predictions for each option, only include the probability itself.

  After reasoning, your response should be in this format:
  <forecast>
  {forecost}

  <probabilities>
  Option "A": A%
  Option "B": B%
  ...
  Option "N": N%
  </probabilities>
  </forecast>
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

@forecasts = []
FORECASTERS.each_with_index do |provider, index|
  Formatador.display "\n[bold][green]# Superforecaster[#{index}: #{provider}]: Forecasting…[/] "
  forecast_json = cache(post_id, "#{index}.forecast.json") do
    llm = case provider
          when :anthropic
            Anthropic.new(temperature: 0.9) # 0-1
          when :perplexity
            Perplexity.new(
              system: SUPERFORECASTER_SYSTEM_PROMPT,
              temperature: 0.9
            ) # 0-2
          end
    forecast_prompt = prompt_with_type(llm, question, shared_forecast_prompt_template)
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

forecast_delphi_prompt_template = ERB.new(<<~FORECAST_DELPHI_PROMPT, trim_mode: '-')
  Review these predictions for the same question from other superforecasters.
  <predictions>
  <%- @forecasts.each do |f| -%>
  <%- next if f == forecast -%>
  <prediction>
  <%= f.content %>
  </prediction>
  <%- end -%>
  </predictions>

  1. Review these forecasts and compare each to your initial forecast. Focus on differences in probabilities, key assumptions, reasoning, and supporting evidence.
  2. Before revising your forecast, show step-by-step reasoning in clear, logical order starting with <reasoning> on the line before and ending with </reasoning> on the line after.
  3. Provide a revised forecast, include your confidence level and note any uncertainties impacting your revision.

FORECAST_DELPHI_PROMPT

forecast_revisions = []
Formatador.display_line "\n[bold][green]# Meta: Optimizing Forecasts[/] "
FORECASTERS.each_with_index do |provider, index|
  forecast = forecasts[index]

  forecast_delphi_prompt = forecast_delphi_prompt_template.result(binding)
  forecast_delphi_prompt = prompt_with_type(question, forecast_delphi_prompt)

  forecast_revision_json = cache(post_id, "#{index}.forecast.1.json") do
    Formatador.display "\n[bold][green]## Superforecaster[#{index}: #{provider}]: Revising Forecast…[/] "
    llm = case provider
          when :anthropic
            Anthropic.new
          when :perplexity
            Perplexity.new(system: SUPERFORECASTER_SYSTEM_PROMPT)
          end
    forecast_delphi_prompt = prompt_with_type(llm, question, forecast_delphi_prompt_template)
    revision = llm.eval(
      { 'role': 'user', 'content': forecast_prompt },
      { 'role': 'assistant', 'content': forecast.content },
      { 'role': 'user', 'content': forecast_delphi_prompt }
    )
    puts revision.content
    revision.to_json
  end
  forecast_revisions << case provider
                        when :anthropic
                          Anthropic::Response.new(data: JSON.parse(forecast_revision_json))
                        when :perplexity
                          Perplexity::Response.new(data: JSON.parse(forecast_revision_json))
                        end
end

consensus_forecast_prompt_template = ERB.new(<<~CONSENSUS_FORECAST_PROMPT_TEMPLATE, trim_mode: '-')
  Review these predictions from other superforecasters.
  <predictions>
  <%- forecasts.each do |forecast| -%>
  <prediction>
  <%= forecast.content %>
  </prediction>
  <%- end -%>
  </predictions>

  - Summarize the consensus as a final forecast.
  - Before summarizing the consensus, show step-by-step reasoning in clear, logical order starting with <reasoning> on the line before and ending with </reasoning> on the line after.

CONSENSUS_FORECAST_PROMPT_TEMPLATE

Formatador.display "\n[bold][green]# Superforecaster: Summarizing Consensus…[/] "
consensus_json = cache(post_id, 'consensus.json') do
  llm = Anthropic.new
  consensus_prompt = prompt_with_type(llm, question, consensus_forecast_prompt_template)
  consensus = llm.eval({ 'role': 'user', 'content': consensus_prompt })
  consensus.to_json
end
revision = Anthropic::Response.new(data: JSON.parse(consensus_json))

Formatador.display_line "\n[bold][green]## Post Prep:[/]"
question.submit(revision)
