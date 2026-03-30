# frozen_string_literal: true

# Put stub gems on the load path before anything else so that `require 'excon'`
# etc. resolve to the local stubs rather than failing on missing gems.
$LOAD_PATH.unshift(File.expand_path('stubs', __dir__))

require 'minitest/autorun'
require 'fileutils'
require 'json'
require 'time'
require 'erb'

# Load bundler first, then stub Bundler.setup so lib files can be loaded
# without the lockfile's exact gem versions being present.
require 'bundler'
module Bundler
  def self.setup(*); end
end

# The stubs above (excon.rb, formatador.rb, reline.rb) satisfy any remaining
# `require 'formatador'` / `require 'excon'` calls inside lib files.

# Ensure formatador's thread-local that utility.rb expects is set up.
require 'formatador'
Thread.current[:formatador] = Formatador.new

# ---------------------------------------------------------------------------
# Load lib files directly (not via script_helpers which re-invokes Bundler)
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
