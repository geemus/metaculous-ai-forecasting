#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/asknews'
require_relative 'lib/script_helpers'

post_id = ARGV[0] || raise('post id argument is required')

question = fetch_question(post_id)
exit if should_skip_forecast?(question, post_id)

CATEGORIES = %w[
  Business
  Climate
  Crime
  Culture
  Entertainment
  Environment
  Finance
  Health
  Military
  Politics
  Science
  Sports
  Technology
  World
].freeze

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
  - Provide a set of the most relevant searchable keywords for general news focusing on core concepts and omitting methodologies to find related information as a comma-separated list, starting with `<query>` on the line before and ending with `</query>` on the line after.
  - Provide the three or fewer best matching categories among [#{CATEGORIES.join(', ')}] as a comma-separated list, starting with `<categories>` on the line before and ending with `</categories>` on the line after.
FILTER_PROMPT_TEMPLATE

Formatador.display "\n[bold][green]# News: Generating Filters[anthropic/claude-haiku-4-5](#{post_id})…[/] "
filters_json = cache(post_id, 'news_filters.json') do
  llm = OpenRouter.new(
    model: 'anthropic/claude-haiku-4.5',
    system: '',
    tools: []
  )
  filters = llm.eval({ 'role': 'user', 'content': filter_prompt })
  puts filters.content
  categories = filters.extracted_content('categories').split(', ')
  categories.select! { |category| CATEGORIES.include?(category) } # ignore category hallucinations
  {
    categories: categories,
    query: filters.extracted_content('query')
  }.to_json
rescue StandardError => e
  puts e
  puts filters.data
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

Formatador.display "\n[bold][green]# News: Summarizing(#{post_id})…[/] "
news_summary = cache(post_id, 'outputs/news_summary.md') do
  llm = OpenRouter.new(
    model: 'anthropic/claude-haiku-4.5',
    system: 'You are a research assistant summarizing news for a forecasting pipeline. Be concise and factual.',
    tools: []
  )
  summary_prompt = <<~PROMPT
    Summarize these news articles into a brief roundup. Include:
    - Article count and date range
    - 3 key themes or developments across the articles
    - The 2-3 most relevant articles for the forecast question (with titles)

    #{news_md}

    Format your response as:
    <news_summary>
    [Your summary here — 4-6 sentences total]
    </news_summary>
  PROMPT
  summary = llm.eval({ role: 'user', content: summary_prompt })
  summary.extracted_content('news_summary')
end
puts news_summary
