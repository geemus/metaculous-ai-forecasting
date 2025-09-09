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
            You are an assistant to a superforecaster.
            The superforecaster will give you a question they intend to forecast on.
            Your role is to generate a concise but detailed summary of the most relevant, credible news and information to inform the forecast.
            Begin by identifying any relevant base rates, historical analogs, or reference classes related to the question.
            Then present a balanced overview of the evidence supporting and opposing each potential outcome, highlighting key facts and uncertainties.
            Indicate whether the current information suggests a leaning towards Yes, No, or if it remains inconclusive, but do not produce forecasts or assign probabilities yourself.
            Before your response, show step-by-step reasoning in clear, logical order starting with <reasoning> on the line before and ending with </reasoning> on the line after.
            Provide your response starting with <summary> on the line before and ending with </summary> on the line after.
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
  <question>
  <%= question[:title] %>
  </question>

  <description>
  <%= question[:description] %>
  </description>
RESEARCH_PROMPT

puts
Formatador.display_line '[bold][green]# Target Forecasting Question[/]'
research_prompt = research_prompt_template.result(binding)
puts research_prompt

puts
Formatador.display_line '[bold][green]# Researcher: Researching…[/]'
research_json = perplexity_completion({ 'role': 'user', 'content': research_prompt })
research_content = research_json['choices'].map { |choice| choice['message']['content'] }.join("\n")

Formatador.display_line("[red] #{research_content} [/]") if ENV['DEBUG']

puts
Formatador.display_line '[bold][green]## Research Output[/]'
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
puts research_output_template.result(binding)
