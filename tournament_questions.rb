#!/usr/bin/env ruby
# frozen_string_literal: true

require './lib/metaculus'

tournament_id = ARGV[0] || raise('tournament id argument is required')

questions = Metaculus.list_tournament_questions(tournament_id)
puts questions.map(&:post_id).join(' ')
