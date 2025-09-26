#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler'
Bundler.setup

require 'erb'
require 'excon'
require 'fileutils'
require 'json'

require './lib/metaculus'
require './lib/perplexity'
require './lib/prompts'
require './lib/utility'

# metaculus test questions: (binary: 578, numeric: 14333, multiple-choice: 22427, discrete: 38880)
post_id = ARGV[0] || raise('post id argument is required')
init_cache(post_id)

Formatador.display "\n[bold][green]# Metaculus: Getting Post(#{post_id})…[/] "
post_json = cache(post_id, 'post.json') do
  Metaculus.get_post(post_id).to_json
end
question = Metaculus::Question.new(data: JSON.parse(post_json))

if question.existing_forecast? && !%w[578 14333 22427 38880].include?(post_id)
  Formatador.display "\n[bold][green]# Skipping: Already Submitted Forecast for #{post_id}[/] "
  exit
end

cache_write(post_id, 'inputs/system.researcher.md', RESEARCHER_SYSTEM_PROMPT)

Formatador.display "\n[bold][green]# Researcher: Drafting Research(#{post_id})…[/] "
cache(post_id, 'research.json') do
  # perplexity = Perplexity.new(model: 'sonar-deep-research')
  perplexity = Perplexity.new(model: 'sonar-pro')
  @research_prompt = FORECAST_PROMPT_TEMPLATE.result(binding)
  cache_write(post_id, 'inputs/research.md', @research_prompt)
  research = perplexity.eval({ 'role': 'user', 'content': @research_prompt })
  cache_write(post_id, 'outputs/research.md', research.content)
  cache_write(post_id, 'reflects/research.md', research.extracted_content('reflect'))
  research.to_json
end
