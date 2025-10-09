#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler'
Bundler.setup

require 'erb'
require 'excon'
require 'fileutils'
require 'json'

require './lib/anthropic'
require './lib/asknews'
require './lib/deepseek'
require './lib/metaculus'
require './lib/openai'
require './lib/perplexity'
require './lib/prompts'
require './lib/utility'

# metaculus test questions: (binary: 578, numeric: 14333, multiple-choice: 22427, discrete: 38880)
post_id = ARGV[0] || raise('post id argument is required')
init_cache(post_id)

Formatador.display "\n[bold][green]# Metaculus: Getting Post(#{post_id})…[/] "
post_json = Metaculus.get_post(post_id).to_json
cache_write(post_id, 'post.json', post_json)
question = Metaculus::Question.new(data: JSON.parse(post_json))

if question.existing_forecast? && !%w[578 14333 22427 38880].include?(post_id)
  Formatador.display "\n[bold][green]# Skipping: Already Submitted Forecast for #{post_id}[/] "
  # exit
end

filter_prompt = ERB.new(<<~FILTER_PROMPT_TEMPLATE, trim_mode: '-').result(binding)
  You are an expert researcher preparing to research this forecast question and background:

  Forecast Question:
  <question>
  <%= question.title %>
  </question>

  Forecast Background:
  <background>
  <%= question.background %>
  </background>

  - Before responding, show step-by-step reasoning in clear, logical order starting with `<<<<<< think` on the line before and ending with `>>>>>>` on the line after.
  <%- unless ENV['GITHUB_ACTIONS'] == 'true' -%>
  - After responding, provide actionable recommendations to improve the prompt's effectiveness with reasoning explanations starting with `<<<<<< reflect` on the line before and ending with `>>>>>>` on the line after.
  <%- end -%>

  - Provide a set of the most relevant searchable keywords for general news focusing on core concepts and omitting methodologies to find related information as a comma-separated list, starting with `<query>` on the line before and ending with `</query>` on the line after.
  - Provide the three or fewer best matching categories among [Business, Crime, Politics, Science, Sports, Technology, Military, Health, Entertainment, Finance, Culture, Climate, Environment, World] as a comma-separated list, starting with `<categories>` on the line before and ending with `</categories>` on the line after.
FILTER_PROMPT_TEMPLATE

Formatador.display "\n[bold][green]# News: Generating Filters[deepseek](#{post_id})…[/] "
filters_json = cache(post_id, 'news_filters.json') do
  deepseek = DeepSeek.new(
    model: 'deepseek-chat',
    system: ''
  )
  filters = deepseek.eval({ 'role': 'user', 'content': filter_prompt })
  puts filters.content
  {
    categories: filters.extracted_content('categories').split(', '),
    query: filters.extracted_content('query')
  }.to_json
end
filters = JSON.parse(filters_json)
puts filters

Formatador.display "\n[bold][green]# News: Searching(#{post_id})…[/] "
news_json = cache(post_id, 'news.json') do
  asknews = AskNews.new
  news_json = asknews.search_news(filters)
  cache_write(post_id, 'news.json', news_json)
  news_json.to_json
end

news = JSON.parse(news_json)
articles = news['as_dicts'][0...6]
news_prompt = ERB.new(<<~NEWS_PROMPT_TEMPLATE, trim_mode: '-')
  Forecast Related News:
  <articles>
  <%- articles.each do |article| -%>
  <article>
  Title: <%= article['eng_title'] %>
  Source: [<%= article['source_id'] %>](<%= article['article_url'] %>)
  Publish Date: <%= article['pub_date'] %>
  Summary: <%= article['summary'] %>
  </article>
  <%- end -%>
  </articles>
NEWS_PROMPT_TEMPLATE

news_md = news_prompt.result(binding)
cache_write(post_id, 'outputs/news.md', news_md)
puts news_md
