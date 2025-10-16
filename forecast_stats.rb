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
