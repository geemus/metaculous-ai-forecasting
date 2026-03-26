#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/script_helpers'

FORECASTERS = Provider::FORECASTERS

post_id = ARGV[0] || raise('post id argument is required')
type = ARGV[1] || raise('type argument is required')

question = load_cached_question(post_id)
@forecasts = load_forecasts(post_id, type: type)

unless question.aggregate_content.empty?
  Formatador.display "\n[bold][green]# Aggregates:[/]\n"
  Formatador.indent do
    question.aggregate_content.split("\n").each { |line| Formatador.display_line(line) }
  end
end

count = @forecasts.count
case question.type
when 'binary'
  values = @forecasts.map(&:probability).map { |p| p.round(10) }
  sorted = values.sort
  Formatador.display "\n[bold][green]# #{type} Stats #{values}: count: #{count}, median: #{sorted_median(sorted)}, stddev: #{stddev(values).round(6)}[/]\n"
when 'numeric', 'discrete'
  values = @forecasts.map { |f| f.percentiles[50] }
  sorted = values.sort
  Formatador.display "\n[bold][green]# #{type} Stats P50 #{values}: count: #{count}, median: #{sorted_median(sorted)}[/]\n"
when 'multiple_choice'
  probabilities = @forecasts.map(&:probabilities)
  probabilities.first.each_key do |key|
    values = probabilities.map { |fp| fp[key].round(10) }
    sorted = values.sort
    Formatador.display "\n[bold][green]# #{type} Stats `#{key}` = #{values}: count: #{count}, median: #{sorted_median(sorted)}, stddev: #{stddev(values).round(6)}[/]"
  end
  puts
end
