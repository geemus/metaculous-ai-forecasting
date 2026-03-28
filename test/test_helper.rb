# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'json'
require 'time'
require 'erb'

# ---------------------------------------------------------------------------
# Load lib files directly. Run tests via `bundle exec rake test` (or
# `bundle exec ruby test/run_tests.rb`) from the repo root so that all
# production gems are available and Bundler.setup in lib files succeeds.
# ---------------------------------------------------------------------------
require_relative '../lib/helpers/response'
require_relative '../lib/utility'
require_relative '../lib/response'
require_relative '../lib/metaculus'
require_relative '../lib/prompts'
require_relative '../lib/tools'
require_relative '../lib/open_router'
require_relative '../lib/perplexity'
require_relative '../lib/deepseek'
require_relative '../lib/openai'
require_relative '../lib/anthropic'
require_relative '../lib/provider'
