#!/usr/bin/env ruby
# frozen_string_literal: true

# metaculus test questions: (binary: 578, numeric: 14333, multiple-choice: 22427, discrete: 38880)
post_id = ARGV[0] || raise('post id argument is required')

`open https://metaculus.com/questions/#{post_id}`
