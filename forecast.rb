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

FileUtils.mkdir_p('./tmp') # setup for cache if missing

def format_research(perplexity_response)
  ERB.new(<<~RESEARCH_OUTPUT, trim_mode: '-').result(binding)
    <summary>
    <%= perplexity_response.extracted_content('summary') %>
    </summary>

    <sources>
    <% perplexity_response.data['search_results'].each do |result| -%>
    - [<%= result['title'] %>](<%= result['url'] %>) <%= result['snippet'] %> (Published: <%= result['date'] %>, Updated: <%= result['last_updated'] %>)
    <% end -%>
    </sources>
  RESEARCH_OUTPUT
end

# metaculus 578 for initial testing
question_id = 578
Formatador.display "\n[bold][green]# Metaculus: Getting Question…[/] "
question_json = cache("#{question_id}.question.json") do
  Metaculus.get_post(question_id).to_json
end
question = Metaculus::Question.new(data: JSON.parse(question_json))

forecast_prompt_template = ERB.new(<<~FORECAST_PROMPT_TEMPLATE, trim_mode: '-')
  Forecast Question:
  <question>
  <%= question.title %>
  </question>

  Forecast Background:
  <background>
  <%= question.background %>
  </background>

  Criteria for determining forecast outcome, which have not yet been met:
  <criteria>
  <%= question.criteria %>
  </criteria>

  Existing Metaculus Forecasts Aggregate:
  <aggregate>
  <count><%= question.latest_count %></count>
  <mean><%= question.latest_mean %>%</mean>
  <median><%= question.latest_median %>%</median>
  </aggregate>
FORECAST_PROMPT_TEMPLATE
forecast_prompt = forecast_prompt_template.result(binding)

Formatador.display_line "\n[bold][green]# Researcher: Research Prompt[/]"
research_prompt = forecast_prompt
puts research_prompt

Formatador.display "\n[bold][green]# Researcher: Drafting Research…[/] "
research_json = cache("#{question_id}.research.0.json") do
  research = Perplexity.eval({ 'role': 'user', 'content': research_prompt })
  research.to_json
end
research = Perplexity::Response.new(data: JSON.parse(research_json))
research_output = format_research(research)
puts research_output

Formatador.display "\n[bold][green]# Meta: Optimizing Research[/] "
revision_json = cache("#{question_id}.research.1.json") do
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
revision_output = format_research(revision)
puts revision_output

Formatador.display_line "\n[bold][green]## Superforecaster: Forecast Prompt[/]"
forecast_prompt_template = ERB.new(<<~FORECAST_PROMPT, trim_mode: '-')
  Create a forecast based on the following information.

  <%= forecast_prompt -%>

  Here is a summary of relevant data from your research assistant:
  <research>
  <%= revision_output %>
  </research>

  - Before providing your forecast, show step-by-step reasoning in clear, logical order starting with <reasoning> on the line before and ending with </reasoning> on the line after.
  - Today is <%= Time.now.strftime('%B %d, %Y') %>. Consider the time remaining before the outcome of the question will become known.
  - Provide your response starting with <forecast> on the line before and ending with </forecast> on the line after.
  - Provide your final probabilistic prediction with <probability> on the line before and ending with </probability> on the line after, only include the probability itself.
FORECAST_PROMPT
forecast_prompt = forecast_prompt_template.result(binding)
puts forecast_prompt

Formatador.display "\n[bold][green]# Superforecaster: Forecasting…[/] "
forecast_json = cache("#{question_id}.forecast.json") do
  forecast = Anthropic.eval({ 'role': 'user', 'content': forecast_prompt })
  forecast.to_json
end
forecast = Anthropic::Response.new(data: JSON.parse(forecast_json))

Formatador.display_line "\n[bold][green]# Forecast:[/] #{question.title}"
puts "Probability: #{forecast.extracted_content('probability')}"
puts forecast.extracted_content('forecast')
