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
require './lib/utility'

Thread.current[:formatador] = Formatador.new
Thread.current[:formatador].instance_variable_set(:@indent, 0)

FORECASTERS = 2

# metaculus test questions: (binary: 578, numeric: 14333, multiple-choice: 22427, discrete: 38880)
question_id = ARGV[0] || raise("ENV['QUESTION_ID'] is required")

# setup directories for cache, if missing
FileUtils.mkdir_p('./tmp')
FileUtils.mkdir_p("./tmp/#{question_id}")

Formatador.display "\n[bold][green]# Metaculus: Getting Question(#{question_id})…[/] "
question_json = cache(question_id, 'question.json') do
  Metaculus.get_post(question_id).to_json
end
question = Metaculus::Question.new(data: JSON.parse(question_json))

forecast_prompt_template = ERB.new(<<~FORECAST_PROMPT_TEMPLATE, trim_mode: '-')
  Forecast Question:
  <question>
  <%= question.title %>
  </question>
  <%- unless question.options.empty? -%>
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
forecast_prompt = forecast_prompt_template.result(binding)
puts forecast_prompt

Formatador.display_line "\n[bold][green]# Researcher: Research Prompt[/]"
research_prompt = forecast_prompt
puts research_prompt

Formatador.display "\n[bold][green]# Researcher: Drafting Research…[/] "
research_json = cache(question_id, 'research.0.json') do
  research = Perplexity.eval({ 'role': 'user', 'content': research_prompt })
  research.to_json
end
research = Perplexity::Response.new(data: JSON.parse(research_json))
research_output = research.formatted_research
puts research_output

Formatador.display_line "\n[bold][green]# Meta: Optimizing Research[/] "
revision_json = cache(question_id, 'research.1.json') do
  Formatador.display_line "\n[bold][green]## Superforecaster: Research Feedback Prompt[/]"
  research_feedback_prompt_template = ERB.new(<<~RESEARCH_FEEDBACK_PROMPT, trim_mode: '-')
    Provide feedback to your assistant on this research for one of your forecasts:
    <research>
    <%= research_output %>
    </research>

    - Before providing feedback, show step-by-step reasoning in clear, logical order starting with <reasoning> on the line before and ending with </reasoning> on the line after.
    - Provide feedback on how to improve this research starting with <feedback> on the line before and ending with </feedback> on the line after.
  RESEARCH_FEEDBACK_PROMPT
  research_feedback_prompt = research_feedback_prompt_template.result(binding)
  puts research_feedback_prompt

  Formatador.display "\n[bold][green]## Superforecaster: Reviewing Research…[/] "
  research_feedback = Anthropic.eval({ 'role': 'user', 'content': research_feedback_prompt })
  puts research_feedback.extracted_content('feedback')

  Formatador.display "\n[bold][green]## Researcher: Revising Research…[/] "
  revision = Perplexity.eval(
    { 'role': 'user', 'content': research_prompt },
    { 'role': 'assistant', 'content': research.stripped_content('reasoning') },
    { 'role': 'user', 'content': research_feedback.extracted_content('feedback') }
  )
  revision.to_json
end
revision = Perplexity::Response.new(data: JSON.parse(revision_json))
revision_output = research.formatted_research
puts revision_output

Formatador.display_line "\n[bold][green]## Superforecaster: Forecast Prompt[/]"
shared_forecast_prompt_template = ERB.new(<<~SHARED_FORECAST_PROMPT, trim_mode: '-')
  Create a forecast based on the following information.

  <%= forecast_prompt -%>

  Here is a summary of relevant data from your research assistant:
  <research>
  <%= revision_output %>
  </research>

  - Before providing your forecast, show step-by-step reasoning in clear, logical order starting with <reasoning> on the line before and ending with </reasoning> on the line after.
  - Today is <%= Time.now.strftime('%B %d, %Y') %>. Consider the time remaining before the outcome of the question will become known.
  - Provide your forecast starting with <forecast> on the line before and ending with </forecast> on the line after.
SHARED_FORECAST_PROMPT
shared_forecast_prompt = shared_forecast_prompt_template.result(binding)

binary_forecast_prompt_template = ERB.new(<<~BINARY_FORECAST_PROMPT, trim_mode: '-')
  <%= shared_forecast_prompt -%>

  - Provide your final probabilistic prediction with <probability> on the line before and ending with </probability> on the line after, only include the probability itself.
BINARY_FORECAST_PROMPT
binary_forecast_prompt = binary_forecast_prompt_template.result(binding)

numeric_forecast_prompt_template = ERB.new(<<~NUMERIC_FORECAST_PROMPT, trim_mode: '-')
  <%= shared_forecast_prompt -%>

  - Finally provide the likelihood that the answer will fall at individual values starting with <probabilities> on the line before and ending with </probabilities> on the line after, only include the probabilities themselves and do not use ranges of values, format like:
  <probabilities>
  Value A: A%
  Value B: B%
  ...
  Value N: N%
  </probabilities>
NUMERIC_FORECAST_PROMPT
numeric_forecast_prompt = numeric_forecast_prompt_template.result(binding)

multiple_choice_prompt_template = ERB.new(<<~MULTIPLE_CHOICE_FORECAST_PROMPT, trim_mode: '-')
  <%= shared_forecast_prompt -%>

  - Provide your final probabilistic prediction with <probability> on the line before and ending with </probability> on the line after, only include the probability itself, format like:
  <probabilities>
  Option "A": A%
  Option "B": B%
  ...
  Option "N": N%
  </probabilities>
MULTIPLE_CHOICE_FORECAST_PROMPT
multiple_choice_prompt = multiple_choice_prompt_template.result(binding)

forecast_prompt = case question.type
                  when 'binary'
                    puts binary_forecast_prompt
                    binary_forecast_prompt
                  when 'discrete', 'numeric'
                    puts numeric_forecast_prompt
                    numeric_forecast_prompt
                  when 'multiple_choice'
                    puts multiple_choice_prompt
                    multiple_choice_prompt
                  else
                    raise "Missing template for type: #{question.type}"
                  end

forecasts = []
FORECASTERS.times do |index|
  Formatador.display "\n[bold][green]# Superforecaster[#{index}]: Forecasting…[/] "
  forecast_json = cache(question_id, "#{index}.forecast.json") do
    forecast = Anthropic.eval({ 'role': 'user', 'content': forecast_prompt })
    forecast.to_json
  end
  forecasts << Anthropic::Response.new(data: JSON.parse(forecast_json))
end

forecast_delphi_prompt_template = ERB.new(<<~FORECAST_DELPHI_PROMPT, trim_mode: '-')
  Review these forecasts for the same question from other superforecasters.
  <forecasts>
  <%- forecasts.each do |f| -%>
  <%- next if f == forecast -%>
  <forecast>
  <%= f.extracted_content('forecast') %>
  </forecast>
  <%- end -%>
  </forecasts>

  - Compare these forecasts to your own, paying particular attention to how and why they differ.
  - Before providing your revised forecast, show step-by-step reasoning in clear, logical order starting with <reasoning> on the line before and ending with </reasoning> on the line after.
  - Provide your revised forecast starting with <forecast> on the line before and ending with </forecast> on the line after.
FORECAST_DELPHI_PROMPT

forecast_revisions = []
Formatador.display_line "\n[bold][green]# Meta: Optimizing Forecasts[/] "
forecasts.each_with_index do |forecast, index|
  Formatador.display_line "\n[bold][green]## Superforecaster[#{index}]: Forecast Optimization Prompt[/]"
  forecast_delphi_prompt = forecast_delphi_prompt_template.result(binding)

  forecast_revision_json = cache(question_id, "#{index}.forecast.1.json") do
    Formatador.display "\n[bold][green]## Superforecaster[#{index}]: Revising Forecast…[/] "
    revision = Anthropic.eval(
      { 'role': 'user', 'content': forecast_prompt },
      { 'role': 'assistant', 'content': forecast.stripped_content('reasoning') },
      { 'role': 'user', 'content': forecast_delphi_prompt }
    )
    puts revision.content
    revision.to_json
  end
  forecast_revisions << Anthropic::Response.new(data: JSON.parse(forecast_revision_json))
end

forecast_revisions.each_with_index do |forecast, index|
  Formatador.display_line "\n[bold][green]# Forecast[#{index}]:[/] #{question.title}"
  Formatador.display_line "\n[bold][green]## Summary:[/]"
  puts forecast.extracted_content('forecast')
  Formatador.display_line "\n[bold][green]## Output:[/]"
  case question.type
  when 'binary'
    probability = forecast.extracted_content('probability')
    puts "Probability: #{probability}"
  when 'discrete', 'numeric'
    puts forecast.extracted_content('probabilities')
    puts 'FIXME: Discrete/Numeric output and parsing'
  when 'multiple_choice'
    probabilities_content = forecast.extracted_content('probabilities')
    probabilities = {}
    probabilities_content.split("\n").each do |line|
      pair = line.split('Option ', 2).last
      key, value = pair.split(': ', 2)
      probabilities[key] = value
    end
    puts format('Probabilities: { %s }', probabilities.map { |k, v| format('%<k>s: %<v>s', k: k, v: v) }.join(', '))
  end
end
