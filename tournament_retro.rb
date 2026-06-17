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
      <id>#{q.post_id}</id>
      <title>#{q.title}</title>
      <type>#{q.type}</type>
      <spot_peer_score>#{q.spot_peer_score.round}</spot_peer_score>
      <resolution>#{q.resolution}</resolution>
      <my_prediction>#{q.my_prediction}</my_prediction>
      <error>#{q.error_summary}</error>
      <my_comment>#{q.my_comment}</my_comment>
    </forecast>
  QUESTION
end

Formatador.display "\n[bold][green]# Retro: Reviewing Scores(#{tournament_id})…[/] "

provider = :deepseek
llm = Provider.new(provider, system: '')

retro_prompt = <<~RETRO_PROMPT
  I am participating in a forecasting tournament. Below are my recent forecasts with scores, resolutions, predictions, error analyses, and my reasoning comments (may be unavailable for some questions — see note).

  <forecasts>
  #{data.join.strip}
  </forecasts>

  Review this data thoroughly, then:
    - identify commonalities among the lowest and highest scores
    - analyze error patterns: direction (over/under confident), magnitude, and question-type trends
    - where comment text is available: evaluate reasoning quality — did comments reveal flawed assumptions, missing base rates, or confirmation bias? If comments are unavailable, note this and rely on score/prediction patterns instead
    - identify distinctions between highest and lowest scores
    - recommend how lower scores could be improved upon (skipping questions is NOT an option)
    - identify which question types I perform best/worst on and why
    - recommend specific, actionable improvements to my forecasting process
    - recommend how to improve this prompt to better analyze results and provide recommendations
RETRO_PROMPT

retro = llm.eval({ 'role': 'user', 'content': retro_prompt })
puts retro.content
