#!/usr/bin/env ruby

# frozen_string_literal: true

require 'bundler'
Bundler.setup

require 'erb'
require 'excon'
require 'formatador'
require 'json'

require './lib/anthropic'
require './lib/metaculus'
require './lib/perplexity'
require './lib/utility'

Thread.current[:formatador] = Formatador.new
Thread.current[:formatador].instance_variable_set(:@indent, 0)

def format_research(perplexity_response)
  research_output_template = ERB.new(<<~RESEARCH_OUTPUT, trim_mode: '-')
    <summary>
    <%= perplexity_response.extracted_content('summary') %>
    </summary>

    <sources>
    <% perplexity_response.json['search_results'].each do |result| -%>
    - [<%= result['title'] %>](<%= result['url'] %>) <%= result['snippet'] %> (Published: <%= result['date'] %>, Updated: <%= result['last_updated'] %>)
    <% end -%>
    </sources>
  RESEARCH_OUTPUT
  research_output = research_output_template.result(binding)
end

# metaculus 578 for initial testing
question = Metaculus.get_post(578)
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
research = Perplexity.eval({ 'role': 'user', 'content': research_prompt })
research_output = format_research(research)
puts research_output

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
puts research_feedback.stripped_content('feedback')

Formatador.display "\n[bold][green]# Researcher: Revising Research…[/] "
revision = Perplexity.eval(
  { 'role': 'user', 'content': research_prompt },
  { 'role': 'assistant', 'content': research.stripped_content('reasoning') },
  { 'role': 'user', 'content': research_feedback.extracted_content('feedback') }
)
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

Formatador.display "\n[bold][green]## Superforecaster: Forecasting…[/] "
forecast = Anthropic.eval({ 'role': 'user', 'content': forecast_prompt })
puts forecast.extracted_content('forecast')

Formatador.display_line "\n[bold][green]## Forecast[/]"
puts "#{question['title']} #{forecast.extracted_content('probability')}"
