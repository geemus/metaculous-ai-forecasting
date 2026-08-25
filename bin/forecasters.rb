#!/usr/bin/env ruby
# frozen_string_literal: true

# Prints the forecaster list as JSON so CI can build a name-keyed matrix
# without hardcoding indices. Run from the repository root.
require 'json'
require './lib/provider'

puts Provider::FORECASTERS.to_json
