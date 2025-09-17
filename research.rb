#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler'
Bundler.setup

require 'erb'
require 'excon'
require 'fileutils'
require 'formatador'
require 'json'

require './lib/metaculus'
require './lib/perplexity'
require './lib/prompts'
require './lib/utility'

Thread.current[:formatador] = Formatador.new
Thread.current[:formatador].instance_variable_set(:@indent, 0)

# metaculus test questions: (binary: 578, numeric: 14333, multiple-choice: 22427, discrete: 38880)
post_id = ARGV[0] || raise('post id argument is required')

FileUtils.mkdir_p("./tmp/#{post_id}") # create cache directory if needed

Formatador.display "\n[bold][green]# Metaculus: Getting Post(#{post_id})…[/] "
post_json = cache(post_id, 'post.json') do
  Metaculus.get_post(post_id).to_json
end
question = Metaculus::Question.new(data: JSON.parse(post_json))

@forecast_prompt = FORECAST_PROMPT_TEMPLATE.result(binding)
puts @forecast_prompt

@research_prompt = @forecast_prompt
Formatador.display "\n[bold][green]# Researcher: Drafting Research…[/] "
research_json = cache(post_id, 'research.json') do
  perplexity = Perplexity.new(model: 'sonar-deep-research')
  research = perplexity.eval({ 'role': 'user', 'content': @research_prompt })
  research.to_json
end
research = Perplexity::Response.new(data: JSON.parse(research_json))
@research_output = research.formatted_research
puts @research_output
