#!/usr/bin/env ruby
# frozen_string_literal: true

# metaculus test questions: (binary: 578, numeric: 14333, multiple-choice: 22427, discrete: 38880)
# metaculus tournaments: minibench, fall-aib-2025
raise('tournament id or post id argument is required') unless ARGV[0]

id = ARGV[0] || raise('post id argument is required')

post_id = if id.to_i.to_s == id
            id
          else
            `./tournament_questions.rb #{id}`.split(' ').first
          end

if post_id.nil? || post_id.empty?
  puts "#{id}: No open/unanswered questions available."
  exit
end

system "./research.rb #{post_id}"
system "echo $(cat tmp/#{post_id}/post.json | jq -r '.title')"
system "echo $(cat tmp/#{post_id}/post.json | jq -r '.question.description')"
0.upto(3).each do |forecaster_index|
  fork { system("./forecast.rb #{post_id} #{forecaster_index}") }
end
Process.waitall
system "./forecast_stats.rb #{post_id} forecast"
0.upto(3).each do |forecaster_index|
  fork { system("./revise_forecast.rb #{post_id} #{forecaster_index}") }
end
Process.waitall
system "./forecast_stats.rb #{post_id} revision"
system "./consensus.rb #{post_id}"
