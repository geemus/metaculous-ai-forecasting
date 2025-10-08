# frozen_string_literal: true

require 'bundler'
Bundler.setup

require 'excon'
require 'formatador'
require 'json'
require 'time'

class AskNews
  def self.search_news(query)
    new.search_news(query)
  end

  def search_news(query)
    start_time = Time.now
    query = get_auto_filter_params(query)
    sleep(10) # wait for (free) rate limit
    excon_response = connection.get(
      path: '/v1/news/search',
      query: query.merge(
        {
          # diversify_sources: true,
          doc_end_delimiter: '</article>',
          doc_start_delimiter: '<article>',
          entity_guarantee_op: 'OR',
          # historical: false,
          # method: 'nl',
          # n_articles: 4, # seems to be ignored
          return_type: 'dicts',
          strategy: 'news knowledge',
          string_guarantee_op: 'OR'
        }
      )
    )
    duration = Time.now - start_time
    Formatador.display_line(
      format(
        '[light_green](in %<minutes>dm %<seconds>ds)[/]',
        minutes: duration / 60, seconds: duration % 60
      )
    )
    JSON.parse(excon_response.body)
  rescue Excon::Error => e
    puts e.response.inspect
    exit(1)
  end

  def self.search_recent_news(query)
    new.search_recent_news(query)
  end

  def search_recent_news(query)
    start_time = Time.now
    excon_response = connection.get(
      path: '/v1/news/search',
      query: {
        diversify_sources: true,
        doc_end_delimiter: '</article>',
        doc_start_delimiter: '<article>',
        historical: false,
        method: 'nl',
        n_articles: 8,
        query: query,
        return_type: 'string'
        # strategy: 'latest news' # method: nl, historical: false, last 24 hours
      }
    )
    duration = Time.now - start_time
    Formatador.display_line(
      format(
        '[light_green](in %<minutes>dm %<seconds>ds)[/]',
        minutes: duration / 60, seconds: duration % 60
      )
    )
    string = JSON.parse(excon_response.body)['as_string']
    data = string.split("\n")
    data.shift
    data.pop
    data.join("\n").strip
    # Question.new(data: JSON.parse(excon_response.body))
  rescue Excon::Error => e
    puts e.response.inspect
    exit(1)
  end

  def self.search_historical_news(query)
    new.search_historical_news(query)
  end

  def search_historical_news(query)
    start_time = Time.now
    excon_response = connection.get(
      path: '/v1/news/search',
      query: {
        # diversify_sources: true,
        doc_end_delimiter: '</article>',
        doc_start_delimiter: '<article>',
        historical: true,
        method: 'nl',
        n_articles: 5, # ? doesn't seem to work
        query: query,
        return_type: 'string'
        # strategy: 'news knowledge' # method: kw, historical: true, past 60 days
      }
    )
    duration = Time.now - start_time
    Formatador.display_line(
      format(
        '[light_green](in %<minutes>dm %<seconds>ds)[/]',
        minutes: duration / 60, seconds: duration % 60
      )
    )
    string = JSON.parse(excon_response.body)['as_string']
    data = string.split("\n")
    data.shift
    data.pop
    data.join("\n").strip
    # Question.new(data: JSON.parse(excon_response.body))
  rescue Excon::Error => e
    puts e.response.inspect
    exit(1)
  end

  private

  def connection
    @connection ||= Excon.new(
      'https://api.asknews.app',
      expects: 200,
      headers: {
        'accept': 'application/json',
        'authorization': "Bearer #{ENV['ASKNEWS_API_KEY']}",
        'content-type': 'application/json'
      }
    )
  end

  def get_auto_filter_params(query)
    excon_response = connection.get(
      path: '/v1/chat/autofilter',
      query: {
        query: query
      }
    )
    data = JSON.parse(excon_response.body)
    data['filter_params'].select { |k, _| %w[categories query].include?(k) }
  rescue Excon::Error => e
    puts e.response.inspect
    exit(1)
  end
end
