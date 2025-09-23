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
puts
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
  Review the following system prompt, assistant prompt, and response:

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
META_RESEARCH_TEMPLATE

Formatador.display "\n[bold][green]# Forecaster: Reviewing Research(#{post_id})…[/] "
meta_research_json = cache(post_id, 'meta_research.json') do
  # perplexity = Perplexity.new(model: 'sonar-deep-research')
  perplexity = Perplexity.new(
    model: 'sonar-pro',
    system: PROMPT_ENGINEER_SYSTEM_PROMPT
  )
  @research_prompt = FORECAST_PROMPT_TEMPLATE.result(binding)
  @meta_research_prompt = META_RESEARCH_TEMPLATE.result(binding)
  cache_write(post_id, 'messages/meta_research_input.md', @meta_research_prompt)
  meta_research = perplexity.eval({ 'role': 'user', 'content': @meta_research_prompt })
  cache_write(post_id, 'messages/meta_research_output.md', meta_research.formatted_research)
  meta_research.to_json
end
meta_research = Perplexity::Response.new(data: JSON.parse(meta_research_json))
puts meta_research.content
