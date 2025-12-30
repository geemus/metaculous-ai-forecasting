#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/script_helpers'

tournament_id = ARGV[0] || raise('tournament id argument is required')

questions = Metaculus.list_resolved_tournament_questions(tournament_id)

puts "NOTE: doesn't paginate, so will miss questions if there are more than 100"

data = []
questions.reject! { |q| q.spot_peer_score.nil? }
questions.sort_by!(&:spot_peer_score)
questions.reverse!
questions.each do |q|
  data << <<~QUESTION
    <forecast>
    <spot_peer_score>#{q.spot_peer_score.round}</spot_peer_score>
    <title>#{q.title}</title>
    </forecast>
  QUESTION
end

Formatador.display "\n[bold][green]# Retro: Reviewing Scores(#{tournament_id})…[/] "

provider = :deepseek
llm = Provider.new(provider, system: '')

retro_prompt = <<~RETRO_PROMPT
I am participating in a forecasting tournament. Below are the titles of some of my recent forecasts and my score, where higher is better.

  <forecasts>
  #{data.join.strip}
  </forecasts>

  Review this data, then:
    - identify commonalities among the lowest and highest scores
    - identify distinctions between highest and lowest scores
    - recommend how lower scores could be improved upon (skipping questions is NOT an option)
    - recommend how to improve this prompt to better analyze results and provide recommendations
RETRO_PROMPT

retro = llm.eval({ 'role': 'user', 'content': retro_prompt })
puts retro.content
