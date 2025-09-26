# frozen_string_literal: true

require 'bundler'
Bundler.setup

require 'formatador'

Thread.current[:formatador] = Formatador.new
Thread.current[:formatador].instance_variable_set(:@indent, 0)

# create cache directories as needed
def init_cache(post_id)
  FileUtils.mkdir_p("./tmp/#{post_id}")
  FileUtils.mkdir_p("./tmp/#{post_id}/consensus")
  FileUtils.mkdir_p("./tmp/#{post_id}/forecasts")
  FileUtils.mkdir_p("./tmp/#{post_id}/inputs")
  FileUtils.mkdir_p("./tmp/#{post_id}/outputs")
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
def extract_xml(tag, text)
  match = text.match(%r{<#{tag}>([\s\S]*?)</#{tag}>})
  match[1].strip if match
end

def strip_xml(tag, text)
  text.gsub(%r{<#{tag}>([\s\S]*?)</#{tag}>}, '').strip
end

def stddev(values)
  average = values.sum / values.count
  deviation_squares = values.map { |v| (v - average) * (v - average) }
  deviation_squares_average = deviation_squares.sum / deviation_squares.count
  Math.sqrt(deviation_squares_average)
end
