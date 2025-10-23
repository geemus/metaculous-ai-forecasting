# frozen_string_literal: true

require 'bundler'
Bundler.setup

require 'formatador'

Thread.current[:formatador] = Formatador.new
Thread.current[:formatador].instance_variable_set(:@indent, 0)

# create cache directories as needed
def init_cache(post_id)
  FileUtils.mkdir_p("./tmp/#{post_id}")
  %w[consensus forecasts inputs outputs].each do |dir|
    FileUtils.mkdir_p("./tmp/#{post_id}/#{dir}")
  end
end

def cache(post_id, path, &block)
  tmp_path = "./tmp/#{post_id}/#{path}"
  if File.exist?(tmp_path)
    File.read(tmp_path)
  else
    data = block.call
    File.write(tmp_path, data)
    data
  end
end

def cache_concat(question_id, path, data)
  tmp_path = "./tmp/#{question_id}/#{path}"
  cached = File.read(tmp_path) if File.exist?(tmp_path)
  File.write(tmp_path, [cached, data].compact.join("\n"))
end

def cache_read!(question_id, path)
  tmp_path = "./tmp/#{question_id}/#{path}"
  raise "Cache Not Found: `#{tmp_path}`" unless File.exist?(tmp_path)

  File.read(tmp_path)
end

def cache_write(question_id, path, data)
  tmp_path = "./tmp/#{question_id}/#{path}"
  File.write(tmp_path, data)
end

# https://github.com/anthropics/anthropic-cookbook/blob/main/patterns/agents/util.py
# https://ruby-doc.org/3.4.1/String.html#method-i-match
def extract_xml(text, *tags)
  extracted = []
  tags.each do |tag|
    regex = %r{<#{tag}>([\s\S]*?)</#{tag}>}
    extracted << text.scan(regex).flatten
  end
  extracted.flatten.map(&:strip)
end

def strip_xml(text, *tags)
  stripped = text.dup
  tags.each do |tag|
    regex = %r{<#{tag}>([\s\S]*)</#{tag}>}
    stripped.gsub!(regex, '')&.strip
  end
  stripped.strip
end

def stddev(values)
  average = values.sum / values.count
  deviation_squares = values.map { |v| (v - average) * (v - average) }
  deviation_squares_average = deviation_squares.sum / deviation_squares.count
  Math.sqrt(deviation_squares_average)
end

# Metaculus test question IDs for development/testing
module TestQuestions
  BINARY = '578'
  NUMERIC = '14333'
  MULTIPLE_CHOICE = '22427'
  DISCRETE = '38880'

  ALL = [BINARY, NUMERIC, MULTIPLE_CHOICE, DISCRETE].freeze

  def self.test_question?(post_id)
    ALL.include?(post_id.to_s)
  end
end

# Check if script should skip a question that already has a forecast
def should_skip_forecast?(question, post_id)
  return false if TestQuestions.test_question?(post_id)

  if question.existing_forecast?
    Formatador.display "\n[bold][green]# Skipping: Already Submitted Forecast for #{post_id}[/] "
    true
  else
    false
  end
end

# Load a question from cache or fetch from API if not cached
def load_question(post_id, fetch: true)
  init_cache(post_id)

  if fetch
    Formatador.display "\n[bold][green]# Metaculus: Getting Post(#{post_id})…[/] "
    post_json = Metaculus.get_post(post_id).to_json
    cache_write(post_id, 'post.json', post_json)
  else
    post_json = cache_read!(post_id, 'post.json')
  end

  Metaculus::Question.new(data: JSON.parse(post_json))
end

# Load cached news
def load_cached_news(post_id)
  cache_read!(post_id, 'outputs/news.md')
end

# Convenience method: load from cache only
def load_cached_question(post_id)
  load_question(post_id, fetch: false)
end

# Convenience method: fetch and cache (default behavior)
def fetch_question(post_id)
  load_question(post_id, fetch: true)
end

# Load all forecasts of a given type for all forecasters
def load_forecasts(post_id, type: 'forecast', forecasters: Provider::FORECASTERS)
  forecasters.each_with_index.map do |provider, index|
    forecast_json = cache_read!(post_id, "forecasts/#{type}.#{index}.json")
    Response.new(provider, json: forecast_json)
  end
end

# Load a single forecast for a specific forecaster
def load_forecast(post_id, forecaster_index, type: 'forecast', forecasters: Provider::FORECASTERS)
  provider = forecasters[forecaster_index]
  forecast_json = cache_read!(post_id, "forecasts/#{type}.#{forecaster_index}.json")
  Response.new(provider, json: forecast_json)
end

# Load research and optionally extract stripped content
def load_research(post_id, strip_tags: nil)
  research_json = cache_read!(post_id, 'research.json')
  research = Response.new(:perplexity, json: research_json)

  if strip_tags
    tags = strip_tags.is_a?(Array) ? strip_tags : [strip_tags]
    research.stripped_content(*tags)
  else
    research
  end
end
