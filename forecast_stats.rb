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
  anthropic
  perplexity
  perplexity
].freeze

# metaculus test questions: (binary: 578, numeric: 14333, multiple-choice: 22427, discrete: 38880)
post_id = ARGV[0] || raise('post id argument is required')
type = ARGV[1] || raise('type argument is required')
init_cache(post_id)

post_json = cache_read!(post_id, 'post.json')
question = Metaculus::Question.new(data: JSON.parse(post_json))
if question.existing_forecast? && !%w[578 14333 22427 38880].include?(post_id)
  Formatador.display "\n[bold][green]# Skipping: Already Submitted Forecast for #{post_id}[/] "
  exit
end

@forecasts = []
FORECASTERS.each_with_index do |provider, index|
  forecast_json = cache_read!(post_id, "forecasts/#{type}.#{index}.json")
  @forecasts << case provider
                when :anthropic
                  Anthropic::Response.new(json: forecast_json)
                when :perplexity
                  Perplexity::Response.new(json: forecast_json)
                end
end

unless question.aggregate_content.empty?
  Formatador.display "\n[bold][green]# Aggregates:[/]\n"
  Formatador.indent do
    question.aggregate_content.split("\n").each { |line| Formatador.display_line(line) }
  end
end

case question.type
when 'binary'
  count = @forecasts.count
  values = @forecasts.map(&:probability).map { |p| p.round(10) }
  sorted = values.sort
  mid = (sorted.count - 1) / 2.0
  median = (sorted[mid.floor] + sorted[mid.ceil]) / 2.0
  median = median.round(3)
  standard_deviation = stddev(values).round(6)
  Formatador.display "\n[bold][green]# #{type} Stats #{values}: count: #{count}, median: #{median}, stddev: #{standard_deviation}[/]\n"
when 'multiple_choice'
  count = @forecasts.count
  probabilities = @forecasts.map(&:probabilities)
  probabilities.first.each_key do |key|
    values = probabilities.map { |forecast_probabilities| forecast_probabilities[key].round(10) }
    sorted = values.sort
    mid = (sorted.count - 1) / 2.0
    median = (sorted[mid.floor] + sorted[mid.ceil]) / 2.0
    median = median.round(3)
    standard_deviation = stddev(values).round(6)
    Formatador.display "\n[bold][green]# #{type} Stats `#{key}` = #{values}: count: #{count}, median: #{median}, stddev: #{standard_deviation}[/]"
  end
  puts
end
