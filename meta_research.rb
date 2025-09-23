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

system "./research.rb #{post_id}"
research_json = cache_read!(post_id, 'research.json')
research = Perplexity::Response.new(data: JSON.parse(research_json))
puts research.content

Formatador.display "\n[bold][green]# Metaculus: Getting Post(#{post_id})…[/] "
post_json = cache(post_id, 'post.json') do
  Metaculus.get_post(post_id).to_json
end
question = Metaculus::Question.new(data: JSON.parse(post_json))

if question.existing_forecast? && !%w[578 14333 22427 38880].include?(post_id)
  Formatador.display "\n[bold][green]# Skipping: Already Submitted Forecast for #{post_id}[/] "
  exit
end

META_RESEARCH_TEMPLATE = ERB.new(<<~META_RESEARCH_TEMPLATE, trim_mode: '-')
  Review the following response in the context of the provided system and assistant prompts:

  # System Prompt
  <system-prompt>
  <%= RESEARCHER_SYSTEM_PROMPT %>
  </system-prompt>

  # Assistant Prompt
  <assistant-prompt>
  <%= @research_prompt %>
  </assistant-prompt>

  # Response
  <response>
  <%= research.content %>
  </response>

  # Instructions
  - Your goal is to ensure future prompts elicit more accurate and relevant research summaries.
  - Identify weaknesses in the response and suggest concrete improvements to the provided system and assistant prompt that would prevent these issues.
  - Structure your feedback as a numbered list and explain the reasoning behind each suggestion.
  - Reference best practices in prompt engineering where relevant.
META_RESEARCH_TEMPLATE

Formatador.display "\n[bold][green]# Forecaster: Reviewing Research(#{post_id})…[/] "
research_review_json = cache(post_id, 'research_review.json') do
  # perplexity = Perplexity.new(model: 'sonar-deep-research')
  perplexity = Perplexity.new(
    model: 'sonar-pro',
    system: SUPERFORECASTER_SYSTEM_PROMPT
  )
  @research_prompt = FORECAST_PROMPT_TEMPLATE.result(binding)
  @meta_research_prompt = META_RESEARCH_TEMPLATE.result(binding)
  cache_write(post_id, 'messages/research_review_input.md', @meta_research_prompt)
  research = perplexity.eval(
    { 'role': 'user', 'content': @research_prompt },
    { 'role': 'assistant', 'content': research.content },
    { 'role': 'user', 'content': @meta_research_prompt }
  )
  cache_write(post_id, 'messages/research_review_output.md', research.formatted_research)
  research.to_json
end
research_review = Perplexity::Response.new(data: JSON.parse(research_review_json))

puts research_review.content
