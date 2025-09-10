#!/usr/bin/env ruby

# frozen_string_literal: true

require 'bundler'
Bundler.setup

require 'erb'
require 'excon'
require 'formatador'
require 'json'

Thread.current[:formatador] = Formatador.new
Thread.current[:formatador].instance_variable_set(:@indent, 0)

# https://github.com/anthropics/anthropic-cookbook/blob/main/patterns/agents/util.py
# https://ruby-doc.org/3.4.1/String.html#method-i-match
def extract_xml(tag, text)
  match = text.match(%r{<#{tag}>([\s\S]*?)</#{tag}>})
  match[1].strip if match
end

def strip_xml(tag, text)
  text.gsub(%r{<#{tag}>([\s\S]*?)</#{tag}>}, '')
end

# https://docs.anthropic.com/en/api/messages
def anthropic_completion(*messages)
  response = Excon.post(
    'https://api.anthropic.com/v1/messages',
    # expects: 200,
    headers: {
      'accept': 'application/json',
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
      'x-api-key': ENV['ANTHROPIC_API_KEY']
    },
    body: {
      # model: 'claude-opus-4-1-20250805',
      model: 'claude-sonnet-4-20250514',
      max_tokens: 2048,
      messages: messages,
      system: <<~SYSTEM,
        You are an experienced superforecaster.
        - Break down complex questions into smaller, measurable parts, evaluate each separately, then synthesize.
        - Begin forecasts from relevant base rates (outside view) before adjusting to specifics (inside view).
        - When evaluating complex uncertainties, consider what is known for certain, what can be estimated, and what remains unknown or uncertain.
        - Embrace uncertainty by recognizing limits of knowledge and avoid false precision.
        - Assign precise numerical likelihoods, like 42%, avoiding vague categories or over-precise decimals.
        - Actively seek out dissenting perspectives and play devil’s advocate to challenge your own views.
        - Explicitly identify key assumptions, rigorously test their validity, and consider how changing them would affect your forecast.
        - Use incremental Bayesian updating to continuously revise your probabilities as new evidence becomes available.
        - Use probabilistic language such as 'there is a 42% chance', 'it is plausible', or 'roughly 42% confidence', and avoid absolute statements to reflect uncertainty.
        - Balance confidence—be decisive but calibrated, avoiding both overconfidence and excessive hedging.
        - Maintain awareness of cognitive biases and actively correct for them.
        - Before your response, show step-by-step reasoning in clear, logical order starting with <reasoning> on the line before and ending with </reasoning> on the line after.
      SYSTEM
      temperature: 0.1
    }.to_json,
    read_timeout: 360
  )
  JSON.parse(response.body)
end

# NOTE: Anthropic API doesn't appear to return cost data
def display_anthropic_meta(json, duration)
  Formatador.display_line(
    format(
      '[light_green](%<input_tokens>d -> %<output_tokens>d tokens in %<minutes>dm %<seconds>ds)[/]',
      {
        input_tokens:
          json.dig('usage', 'input_tokens') +
          json.dig('usage', 'cache_creation_input_tokens') +
          json.dig('usage', 'cache_read_input_tokens'),
        output_tokens: json.dig('usage', 'output_tokens'),
        minutes: duration / 60,
        seconds: duration % 60
      }
    )
  )
end

# https://docs.perplexity.ai/api-reference/chat-completions-post
def perplexity_completion(*messages)
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
            You are an experienced assistant to a superforecaster.
            - The superforecaster will give you a question they intend to forecast on.
            - Your role is to generate a concise but detailed summary of the most relevant, credible news and information to inform the forecast.
            - Begin by identifying any relevant base rates, historical analogs, or reference classes related to the question.
            - Then present a balanced overview of the evidence supporting and opposing each potential outcome, highlighting key facts and uncertainties.
            - Indicate whether the current information suggests a leaning towards Yes, No, or if it remains inconclusive, but do not produce forecasts or assign probabilities yourself.
            - Before your response, show step-by-step reasoning in clear, logical order starting with <reasoning> on the line before and ending with </reasoning> on the line after.
            - Provide your response starting with <summary> on the line before and ending with </summary> on the line after.
          SYSTEM
        }
      ].concat(messages),
      temperature: 0.1
    }.to_json,
    read_timeout: 360
  )
  JSON.parse(response.body)
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
research_duration = Time.now
research_json = perplexity_completion({ 'role': 'user', 'content': research_prompt })
research_duration = Time.now - research_duration
research_content = research_json['choices'].map { |choice| choice['message']['content'] }.join("\n")
display_perplexity_meta(research_json, research_duration)

research_output_template = ERB.new(<<~RESEARCH_OUTPUT, trim_mode: '-')
  <summary>
  <%= extract_xml('summary', research_content) %>
  </summary>

  <sources>
  <% research_json['search_results'].each do |result| -%>
  - [<%= result['title'] %>](<%= result['url'] %>) <%= result['snippet'] %> (Published: <%= result['date'] %>, Updated: <%= result['last_updated'] %>)
  <% end -%>
  </sources>
RESEARCH_OUTPUT
research_output = research_output_template.result(binding)
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
research_feedback_duration = Time.now
research_feedback_json = anthropic_completion({ 'role': 'user', 'content': research_feedback_prompt })
research_feedback_duration = Time.now - research_feedback_duration
research_feedback_text_array = research_feedback_json['content'].select { |content| content['type'] == 'text' }
research_feedback_content = research_feedback_text_array.map { |content| content['text'] }.join("\n")
display_anthropic_meta(research_feedback_json, research_feedback_duration)
puts extract_xml('feedback', research_feedback_content)

puts
Formatador.display '[bold][green]# Researcher: Revising Research…[/] '
revision_duration = Time.now
revision_json = perplexity_completion(
  { 'role': 'user', 'content': research_prompt },
  { 'role': 'assistant', 'content': strip_xml('reasoning', research_content) },
  { 'role': 'user', 'content': extract_xml('feedback', research_feedback_content) }
)
revision_duration = Time.now - revision_duration
revision_content = revision_json['choices'].map { |choice| choice['message']['content'] }.join("\n")
display_perplexity_meta(revision_json, revision_duration)

revision_output_template = ERB.new(<<~REVISION_OUTPUT, trim_mode: '-')
  <summary>
  <%= extract_xml('summary', revision_content) %>
  </summary>

  <sources>
  <% revision_json['search_results'].each do |result| -%>
  - [<%= result['title'] %>](<%= result['url'] %>) <%= result['snippet'] %> (Published: <%= result['date'] %>, Updated: <%= result['last_updated'] %>)
  <% end -%>
  </sources>
REVISION_OUTPUT
revision_output = revision_output_template.result(binding)
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
forecast_duration = Time.now
forecast_json = anthropic_completion({ 'role': 'user', 'content': forecast_prompt })
forecast_duration = Time.now - forecast_duration
forecast_text_array = forecast_json['content'].select { |content| content['type'] == 'text' }
forecast_content = forecast_text_array.map { |content| content['text'] }.join("\n")
display_anthropic_meta(forecast_json, forecast_duration)
puts extract_xml('forecast', forecast_content)

puts
Formatador.display_line '[bold][green]## Forecast[/]'
puts "#{question['title']} #{extract_xml('probability', forecast_content)}"
