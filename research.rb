#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/script_helpers'
require './lib/anthropic'
require './lib/openai'
require './lib/perplexity'

post_id = ARGV[0] || raise('post id argument is required')

question = fetch_question(post_id)
exit if should_skip_forecast?(question, post_id)

cache_write(post_id, 'inputs/system.researcher.md', RESEARCHER_SYSTEM_PROMPT)

@news_output = load_cached_news(post_id)

Formatador.display "\n[bold][green]# Researcher: Drafting Research(#{post_id})…[/] "
cache(post_id, 'research.json') do
  perplexity = Perplexity.new(model: 'sonar-pro')
  @forecast_prompt = FORECAST_PROMPT_TEMPLATE.result(binding)
  @research_prompt = RESEARCH_PROMPT_TEMPLATE.result(binding)
  cache_write(post_id, 'inputs/research.md', @research_prompt)
  research = perplexity.eval({ 'role': 'user', 'content': @research_prompt })
  cache_write(post_id, 'outputs/research.md', research.content)
  cache_concat(post_id, 'reflects.md',
               "# Research\n#{research.extracted_content('reflect')}\n\n")
  research.to_json
end
