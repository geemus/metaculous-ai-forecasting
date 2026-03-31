# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'json'
require 'time'
require 'erb'
require 'formatador'

Thread.current[:formatador] = Formatador.new

require_relative '../lib/helpers/response'
require_relative '../lib/utility'
require_relative '../lib/response'
require_relative '../lib/metaculus'
require_relative '../lib/prompts'
require_relative '../lib/tools'
require_relative '../lib/open_router'
require_relative '../lib/perplexity'
require_relative '../lib/deepseek'
require_relative '../lib/provider'
