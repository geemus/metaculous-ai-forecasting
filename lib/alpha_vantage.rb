# frozen_string_literal: true

require 'bundler'
Bundler.setup

require 'excon'
require 'formatador'
require 'json'
require 'time'

class AlphaVantage
  def self.get_price(symbol)
    new.get_price(symbol)
  end

  def get_price(symbol)
    start_time = Time.now
    excon_response = connection.get(
      path: 'query',
      query: {
        apikey: ENV['ALPHA_VANTAGE_API_KEY'],
        function: 'GLOBAL_QUOTE',
        symbol: symbol
      }
    )
    duration = Time.now - start_time
    Formatador.display_line(
      format(
        '[light_green](in %<minutes>dm %<seconds>ds)[/]',
        minutes: duration / 60, seconds: duration % 60
      )
    )
    data = JSON.parse(excon_response.body)
    data.dig('Global Quote', '05. price')
  rescue Excon::Error => e
    puts e.response.inspect
    exit(1)
  end

  private

  def connection
    @connection ||= Excon.new(
      'https://www.alphavantage.co',
      expects: 200
    )
  end
end
