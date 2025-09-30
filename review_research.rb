#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler'
Bundler.setup

require 'erb'
require 'excon'
require 'fileutils'
require 'json'

require './lib/anthropic'
require './lib/metaculus'
require './lib/perplexity'
require './lib/prompts'
require './lib/utility'

FORECASTERS = %i[
  anthropic
  perplexity
].freeze

# metaculus test questions: (binary: 578, numeric: 14333, multiple-choice: 22427, discrete: 38880)
post_id = ARGV[0] || raise('post id argument is required')
forecaster_index = ARGV[1]&.to_i || raise('forecaster index argv[1] is required')
init_cache(post_id)

post_json = Metaculus.get_post(post_id).to_json
cache_write(post_id, 'post.json', post_json)
question = Metaculus::Question.new(data: JSON.parse(post_json))
if question.existing_forecast? && !%w[578 14333 22427 38880].include?(post_id)
  Formatador.display "\n[bold][green]# Skipping: Already Submitted Forecast for #{post_id}[/] "
  exit
end

research_json = cache_read!(post_id, 'research.json')
research = Perplexity::Response.new(json: research_json)
@research_output = research.stripped_content('reflect')

provider = FORECASTERS[forecaster_index]

Formatador.display "\n[bold][green]# Forecaster: Reviewing Research(#{post_id})…[/] "
cache(post_id, "research.revision.#{forecaster_index}.json") do
  llm_args = {
    system: '',
    temperature: 0.1
  }
  llm = case provider
        when :anthropic
          Anthropic.new(**llm_args)
        when :perplexity
          Perplexity.new(**llm_args)
        end

  research_prompt = FORECAST_PROMPT_TEMPLATE.result(binding)
  review_research_prompt = REVIEW_RESEARCH_PROMPT_TEMPLATE.result(binding)

  cache_write(post_id, "inputs/research.revision.#{forecaster_index}.md", review_research_prompt)
  revision = llm.eval(
    { 'role': 'user', 'content': research_prompt },
    { 'role': 'assistant', 'content': @research_output },
    { 'role': 'user', 'content': review_research_prompt }
  )
  puts revision.content
  cache_write(post_id, "outputs/research.revision.#{forecaster_index}.md", revision.content)
  cache_concat(post_id, 'reflects.md',
               "# Research Revision #{provider}\n#{revision.extracted_content('reflect')}\n\n")
  revision.to_json
end
