#!/usr/bin/env ruby
# frozen_string_literal: true

require './lib/metaculus'

tournament_id = ARGV[0] || raise('tournament id argument is required')

Formatador.display "\n[bold][green]# Metaculus: Getting Tournament Questions(#{tournament_id})…[/] "
questions = Metaculus.list_tournament_questions(tournament_id)

puts questions.map(&:post_id).inspect
