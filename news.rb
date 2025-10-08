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
  exit
end

Formatador.display "\n[bold][green]# News: Searching(#{post_id})…[/] "
news_json = cache(post_id, 'news.json') do
  asknews = AskNews.new
  news_prompt = [question.background, question.title].join("\n")
  cache_write(post_id, 'inputs/news.md', news_prompt)
  news_json = asknews.search_news(news_prompt)
  # cache_write(post_id, 'outputs/news.md', news)
  cache_write(post_id, 'news.json', news_json)
  news_json.to_json
end

news = JSON.parse(news_json)
articles = news['as_dicts'][0...8]
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
