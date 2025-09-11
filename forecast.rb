#!/usr/bin/env ruby

# frozen_string_literal: true

require 'bundler'
Bundler.setup

require 'erb'
require 'excon'
require 'formatador'
require 'json'

require './lib/anthropic'
require './lib/utility'

Thread.current[:formatador] = Formatador.new
Thread.current[:formatador].instance_variable_set(:@indent, 0)

# https://docs.perplexity.ai/api-reference/chat-completions-post
def perplexity_completion(*messages)
  start_time = Time.now
  response = Excon.post(
    'https://api.perplexity.ai/chat/completions',
    expects: 200,
    headers: {
      'accept': 'application/json',
      'authorization': "Bearer #{ENV['PERPLEXITY_API_KEY']}",
      'content-type': 'application/json'
    },
    body: {
      model: 'sonar-pro',
      messages: [
        {
          'role': 'system',
          'content': <<~SYSTEM
            You are an experienced research assistant for a superforecaster.
            - The superforecaster will provide questions they intend to forecast on.
            - Generate research summaries that are concise yet sufficiently detailed to support forecasting.
            - Do not comment or speculate beyond what what is supported by the evidence.

            - Check for base rate quantifications and meta-analytic summaries.
            - Assess evidence quality, source credibility, and methodological limitations.
            - Identify and state critical assumptions underlying the question, evidence, and scenarios.
            - Flag uncertainties, and information gaps. Characterize the type of uncertainty and impact on the forecast.
            - Flag insufficient, inconclusive, outdated, and contradictory evidence.
            - Flag potential cognitive and source biases.

            - Begin by identifying any relevant base rates, historical analogs or precedents, and reference classes.
            - Then systematically list supporting and opposing evidence for each potential outcome, highlighting key facts and uncertainties.
            - Indicate which outcome current information suggests or if it remains inconclusive, but do not produce forecasts or assign probabilities yourself.
            - Finally, note where further research would improve confidence.
            - Before your response, show step-by-step reasoning in clear, logical order starting with <reasoning> on the line before and ending with </reasoning> on the line after.
            - Provide your response starting with <summary> on the line before and ending with </summary> on the line after.
          SYSTEM
        }
      ].concat(messages),
      temperature: 0.1
    }.to_json,
    read_timeout: 360
  )
  duration = Time.now - start_time
  json = JSON.parse(response.body)
  display_perplexity_meta(json, duration)
  json
rescue Excon::Error => e
  puts e
  exit
end

def display_perplexity_meta(json, duration)
  Formatador.display_line(
    format(
      '[light_green](%<input_tokens>d -> %<output_tokens>d tokens in %<minutes>dm %<seconds>ds @ $%<cost>0.2f)[/]',
      {
        input_tokens: json.dig('usage', 'prompt_tokens'),
        output_tokens: json.dig('usage', 'total_tokens') - json.dig('usage', 'prompt_tokens'),
        minutes: duration / 60,
        seconds: duration % 60,
        cost: json.dig('usage', 'cost', 'total_cost')
      }
    )
  )
end

def extract_perplexity_content(json)
  json['choices'].map { |choice| choice['message']['content'] }.join("\n")
end

def get_metaculus_post(post_id)
  response = Excon.get(
    "https://www.metaculus.com/api/posts/#{post_id}/",
    expects: 200,
    headers: {
      'accept': 'application/json',
      # 'authorization': "Token #{ENV['METACULUS_API_TOKEN']}"
    }
  )
  JSON.parse(response.body)
end

def format_research(json)
  content = extract_perplexity_content(json)
  research_output_template = ERB.new(<<~RESEARCH_OUTPUT, trim_mode: '-')
    <summary>
    <%= extract_xml('summary', content) %>
    </summary>

    <sources>
    <% json['search_results'].each do |result| -%>
    - [<%= result['title'] %>](<%= result['url'] %>) <%= result['snippet'] %> (Published: <%= result['date'] %>, Updated: <%= result['last_updated'] %>)
    <% end -%>
    </sources>
  RESEARCH_OUTPUT
  research_output = research_output_template.result(binding)
end

# metaculous 578 for initial testing
metaculus_json = get_metaculus_post(578)
metaculus_latest_aggregations = metaculus_json.dig('question', 'aggregations', 'recency_weighted', 'latest')
metaculus_latest_count = metaculus_latest_aggregations['forecaster_count']
metaculus_latest_mean = (metaculus_latest_aggregations['means'].first * 100).round
metaculus_latest_median = (metaculus_latest_aggregations['centers'].first * 100).round
question = metaculus_json['question']

forecast_prompt_template = ERB.new(<<~FORECAST_PROMPT_TEMPLATE, trim_mode: '-')
  Forecast Question:
  <question>
  <%= question['title'] %>
  </question>

  Forecast Background:
  <background>
  <%= question['description'] %>
  </background>

  Criteria for determining forecast outcome, which have not yet been met:
  <criteria>
  <%= [question['resolution_criteria'], question['fine_print']].compact.join("\n\n").strip %>
  </criteria>

  Existing Metaculus Forecasts Aggregate:
  <aggregate>
    <count><%= metaculus_latest_count %></count>
    <mean><%= metaculus_latest_mean %>%</mean>
    <median><%= metaculus_latest_median %>%</median>
  </aggregate>
FORECAST_PROMPT_TEMPLATE
forecast_prompt = forecast_prompt_template.result(binding)

puts
Formatador.display_line '[bold][green]# Researcher: Research Prompt[/]'
research_prompt = forecast_prompt
puts research_prompt

puts
Formatador.display '[bold][green]# Researcher: Drafting Research…[/] '
research_json = perplexity_completion({ 'role': 'user', 'content': research_prompt })
research_content = extract_perplexity_content(research_json)
research_output = format_research(research_json)
puts research_output

puts
Formatador.display_line '[bold][green]## Superforecaster: Research Feedback Prompt[/]'
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

puts
Formatador.display '[bold][green]## Superforecaster: Reviewing Research…[/] '
research_feedback = Anthropic.eval({ 'role': 'user', 'content': research_feedback_prompt })
puts research_feedback.content

puts
Formatador.display '[bold][green]# Researcher: Revising Research…[/] '
revision_json = perplexity_completion(
  { 'role': 'user', 'content': research_prompt },
  { 'role': 'assistant', 'content': strip_xml('reasoning', research_content) },
  { 'role': 'user', 'content': research_feedback.extracted_content('feedback') }
)
revision_output = format_research(revision_json)
puts revision_output

Formatador.display_line '[bold][green]## Superforecaster: Forecast Prompt[/]'
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

puts
Formatador.display '[bold][green]## Superforecaster: Forecasting…[/] '
forecast = Anthropic.eval({ 'role': 'user', 'content': forecast_prompt })
puts forecast.extracted_content('forecast')

puts
Formatador.display_line '[bold][green]## Forecast[/]'
puts "#{question['title']} #{forecast.extracted_content('probability')}"
