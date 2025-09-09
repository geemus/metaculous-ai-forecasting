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
      max_tokens: 1024,
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

# metaculous 578 for initial testing
question = {
  'title': 'Will humans go extinct before 2100?',
  'description': "While the general feeling of most people, especially now that the cold war is (mostly) over, is that the risk of human extinction is extremely small, experts have assigned a significantly higher probability to the event.\n\nIn 2008 an [informal poll at the Global Catastrophic Risk Conference at the University of Oxford](https://www.webcitation.org/6YxiCAV0p?url=http://www.fhi.ox.ac.uk/gcr-report.pdf) yielded a median probability of human extinction by 2100 of 19%. Yet, one might want to be cautious when using this result as a good estimate of the true probability of human extinction, as there may be a powerful selection effect at play. Only those who assign a high probability to human extinction are likely to attend the Global Catastrophic Risk Conference in the first place, meaning that the survey was effectively sampling opinions from one extreme tail of the opinion distribution on the subject. Indeed, the conference report itself stated that the findings should be taken 'with a grain of salt'.",
  'fine_print': '',
  'resolution_criteria': "This question will resolve as **Yes** if there are no known humans alive on January 1, 2100.  For these purposes we'll define humans as biological creatures who have as their ancestors – via a chain of live births from mothers –  circa 2000 humans OR who could mate with circa 2000 humans to produce viable offspring. (So AIs, ems, genetically engineered beings of a different species brought up in artificial wombs, etc. would not count).  Any living humans living anywhere in the observable universe (or multiverse) (who are known to the entities operating Metaculus) on that date will be sufficient to resolve the question negatively.\n\nN.B. Even though it is obviously the case that if human extinction occurs Metaculus points won't be very valuable anymore and that it will be practically impossible to check for true human extinction (zero humans left), I would like to ask people not to let this fact influence their prediction and to predict in good faith",
  'type': 'binary'
}

# https://github.com/ruby/erb
research_prompt_template = ERB.new(<<~RESEARCH_PROMPT, trim_mode: '-')
  Question:
  <question>
  <%= question[:title] %>
  </question>

  Background:
  <background>
  <%= question[:description] %>
  </background>

  Criteria for determining outcome, which have not yet been met:
  <criteria>
  <%= question[:resolution_criteria] %>

  <%= question[:fine_print] %>
  </criteria>
RESEARCH_PROMPT

puts
Formatador.display_line '[bold][green]# Researcher: Research Prompt[/]'
research_prompt = research_prompt_template.result(binding)
puts research_prompt

puts
Formatador.display_line '[bold][green]# Researcher: Researching…[/]'
research_json = perplexity_completion({ 'role': 'user', 'content': research_prompt })
research_content = research_json['choices'].map { |choice| choice['message']['content'] }.join("\n")

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

if ENV['DEBUG']
  puts
  Formatador.display_line("[red] #{research_content} [/]")
  puts
  Formatador.display_line '[bold][green]## Researcher: Research Output[/]'
  puts research_output
end

puts
Formatador.display_line '[bold][green]## Superforecaster: Forecast Prompt[/]'
forecast_prompt_template = ERB.new(<<~FORECAST_PROMPT, trim_mode: '-')
  Create a forecast based on the following information.

  Question:
  <question>
  <%= question[:title] %>
  </question>

  Background:
  <background>
  <%= question[:description] %>
  </background>

  Criteria for determining outcome, which have not yet been met:
  <criteria>
  <%= question[:resolution_criteria] %>

  <%= question[:fine_print] %>
  </criteria>

  Here is a summary of relevant data from your research assistant:
  <research>
  <%= research_output %>
  </research>

  - Today is <%= Time.now.strftime('%Y-%m-%d') %>. Consider the time remaining before the outcome of the question in known.
  - Provide your response starting with <forecast> on the line before and ending with </forecast> on the line after.
  - Provide your final probabilistic prediction with <probability> on the line before and ending with </probability> on the line after, only include the probability itself.
FORECAST_PROMPT
forecast_prompt = forecast_prompt_template.result(binding)
puts forecast_prompt

puts
Formatador.display_line '[bold][green]## Superforecaster: Forecasting…[/]'
forecast_json = anthropic_completion({ 'role': 'user', 'content': forecast_prompt })
forecast_text_array = forecast_json['content'].select { |content| content['type'] == 'text' }
forecast_content = forecast_text_array.map { |content| content['text'] }.join("\n")

puts forecast_content

puts
Formatador.display_line '[bold][green]## Forecast[/]'
puts "#{question[:title]} #{extract_xml('probability', forecast_content)}"
