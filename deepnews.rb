#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/asknews'
require_relative 'lib/script_helpers'

post_id = ARGV[0] || raise('post id argument is required')

question = fetch_question(post_id)
exit if should_skip_forecast?(question, post_id)

deepnews_prompt = ERB.new(<<~DEEPNEWS_PROMPT_TEMPLATE, trim_mode: '-').result(binding)
  You are an expert researcher preparing to research this forecast question and background to provide related news content to a superforecaster.

  Forecast Question:
  <question>
  <%= question.title %>
  </question>

  Forecast Background:
  <background>
  <%= question.background %>
  </background>

  Provide detailed news content for the superforecaster to use in an upcoming forecast.
DEEPNEWS_PROMPT_TEMPLATE
cache_write(post_id, 'inputs/deepnews.md', deepnews_prompt)

Formatador.display "\n[bold][green]# AskNews: DeepNews(#{post_id})…[/] "
deepnews_json = cache(post_id, 'deepnews.json') do
  llm = OpenAI.new(
    model: 'deepseek-basic',
    options: { # FIXME: limits imposed by metaculus credits
      max_depth: 2,
      return_sources: false,
      search_depth: 2,
      sources: ['asknews']
    },
    system: '',
    token: ENV['ASKNEWS_API_KEY'],
    url: 'https://api.asknews.app/v1/chat/deepnews'
  )
  deepnews_json = llm.eval({ 'role': 'user', 'content': deepnews_prompt })
  cache_write(post_id, 'deepnews.json', deepnews_json)
  deepnews_json.to_json
end

deepnews_data = JSON.parse(deepnews_json)
deepnews_md = extract_xml(deepnews_data['choices'].first.dig('message', 'content'), 'final_answer').join("\n") + "\n"
cache_write(post_id, 'outputs/deepnews.md', deepnews_md)
puts deepnews_md
