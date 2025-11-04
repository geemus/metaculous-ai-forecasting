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

cache(post_id, 'research.json') do
  Formatador.display "\n[bold][green]# Researcher: Outlining(#{post_id})…[/] "
  llm = Perplexity.new
  @forecast_prompt = FORECAST_PROMPT_TEMPLATE.result(binding)
  @research_outline_prompt = RESEARCH_OUTLINE_PROMPT_TEMPLATE.result(binding)
  cache_write(post_id, 'inputs/research_outline.md', @research_outline_prompt)
  research_outline = llm.eval({ 'role': 'user', 'content': @research_outline_prompt })
  cache_write(post_id, 'outputs/research_outline.md', research_outline.content)
  cache_concat(post_id, 'reflects.md',
               "# Research Outline\n#{research_outline.extracted_content('reflect')}\n\n")

  Formatador.display "\n[bold][green]# Researcher: Drafting(#{post_id})…[/] "
  @research_draft_prompt = RESEARCH_DRAFT_PROMPT_TEMPLATE.result(binding)
  cache_write(post_id, 'inputs/research_draft.md', @research_draft_prompt)
  research_draft = llm.eval(
    { 'role': 'user', 'content': @research_outline_prompt },
    { 'role': 'assistant', 'content': research_outline.stripped_content('reflect') },
    { 'role': 'user', 'content': @research_draft_prompt }
  )
  cache_write(post_id, 'outputs/research.md', research_draft.content)
  cache_concat(post_id, 'reflects.md',
               "# Research\n#{research_draft.extracted_content('reflect')}\n\n")
  research_draft.to_json
end
