# frozen_string_literal: true

# Common requires for all scripts
require 'bundler'
Bundler.setup

require 'erb'
require 'excon'
require 'fileutils'
require 'json'

require_relative 'provider'
require_relative 'response'
require_relative 'metaculus'
require_relative 'prompts'
require_relative 'utility'
