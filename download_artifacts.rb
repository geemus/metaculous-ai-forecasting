#!/usr/bin/env ruby
# frozen_string_literal: true

require 'cgi'
require 'excon'
require 'fileutils'
require 'json'
require 'zip'

artifact_id = ARGV[0] || raise('artifact id argv[0] is required')

api_key = ENV['METACULUS_AI_FORECASTING_GITHUB_TOKEN']
github = Excon.new(
  'https://api.github.com',
  headers: {
    'Accept': 'application/vnd.github+json',
    'Authorization': "Bearer #{api_key}",
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'geemus/metaculus-ai-forecasting'
  }
)

artifact_response = github.get(path: "/repos/geemus/metaculus-ai-forecasting/actions/artifacts/#{artifact_id}")
name = JSON.parse(artifact_response.body)['name']
id, path = name.split('.', 2)
FileUtils.mkdir_p("./tmp/artifacts/#{id}")

location_response = github.get(path: "/repos/geemus/metaculus-ai-forecasting/actions/artifacts/#{artifact_id}/zip")
location = location_response.headers['Location']

artifact_response = Excon.get(location)
Zip::File.open_buffer(StringIO.new(artifact_response.body)) do |io|
  entry = io.first
  data = entry.get_input_stream.read

  tmp_path = "./tmp/artifacts/#{id}/#{path}"
  File.write(tmp_path, data)
  puts "Wrote #{tmp_path}"
end
