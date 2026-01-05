#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative('lib/provider')

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

system "./news.rb #{post_id}"
system "./tools_research.rb #{post_id}"
system "echo $(cat tmp/#{post_id}/post.json | jq -r '.title')"
system "echo $(cat tmp/#{post_id}/post.json | jq -r '.question.description')"
Provider::FORECASTERS.count.times do |forecaster_index|
  fork { system("./forecast.rb #{post_id} #{forecaster_index}") }
end
Process.waitall
system "./forecast_stats.rb #{post_id} forecast"
Provider::FORECASTERS.count.times do |forecaster_index|
  fork { system("./revise_forecast.rb #{post_id} #{forecaster_index}") }
end
Process.waitall
system "./forecast_stats.rb #{post_id} revision"
system "./consensus.rb #{post_id}"
