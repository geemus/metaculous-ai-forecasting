# frozen_string_literal: true

require 'bundler'
Bundler.setup

require 'excon'
require 'formatador'
require 'json'
require 'time'

class AskNews
  def search_latest_news(query)
    start_time = Time.now
    excon_response = connection.get(
      path: '/v1/news/search',
      query: {
        query: query,
        return_type: 'string',
        strategy: 'latest news'
      }
    )
    duration = Time.now - start_time
    Formatador.display_line(
      format(
        '[light_green](in %<minutes>dm %<seconds>ds)[/]',
        minutes: duration / 60, seconds: duration % 60
      )
    )
    JSON.parse(excon_response.body)
    # Question.new(data: JSON.parse(excon_response.body))
  rescue Excon::Error => e
    puts e.response.inspect
    exit(1)
  end

  def search_historical_news(query)
    start_time = Time.now
    excon_response = connection.get(
      path: '/v1/news/search',
      query: {
        query: query,
        return_type: 'string',
        strategy: 'news knowledge'
      }
    )
    duration = Time.now - start_time
    Formatador.display_line(
      format(
        '[light_green](in %<minutes>dm %<seconds>ds)[/]',
        minutes: duration / 60, seconds: duration % 60
      )
    )
    JSON.parse(excon_response.body)
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
end
