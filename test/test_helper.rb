# frozen_string_literal: true

# Coverage must be started before any lib files are loaded.
require 'coverage'
Coverage.start(lines: true)

at_exit do
  results = Coverage.result

  lib_root = File.expand_path('../lib', __dir__)
  lib_files = results.select { |path, _| path.start_with?(lib_root) }

  total_lines = 0
  covered_lines = 0
  uncovered_files = []

  lib_files.each do |path, data|
    lines = data[:lines]
    relevant = lines.compact  # nil = non-executable; 0/N = executable
    file_total = relevant.size
    file_covered = relevant.count { |n| n > 0 }

    total_lines += file_total
    covered_lines += file_covered

    uncovered_files << [path, file_total, file_covered] if file_covered < file_total
  end

  pct = total_lines > 0 ? (covered_lines.to_f / total_lines * 100).round(1) : 0.0

  puts "\n--- Coverage Report ---"
  puts "Covered lines : #{covered_lines} / #{total_lines} (#{pct}%)"

  if uncovered_files.any?
    puts "\nFiles with uncovered lines:"
    uncovered_files.sort_by { |_, t, c| c.to_f / [t, 1].max }.each do |path, t, c|
      short = path.sub("#{lib_root}/", 'lib/')
      file_pct = t > 0 ? (c.to_f / t * 100).round(1) : 0.0
      puts "  #{file_pct.to_s.rjust(5)}%  #{short}  (#{c}/#{t} lines)"
    end
  end

  puts "-----------------------\n"

  # Uncomment and raise the threshold as test coverage improves:
  # minimum_coverage = 80
  # if pct < minimum_coverage
  #   warn "Coverage #{pct}% is below minimum #{minimum_coverage}%"
  #   exit 1
  # end
end

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
