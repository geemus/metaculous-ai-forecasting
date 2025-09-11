# frozen_string_literal: true

class Metaculus
  def self.get_post(id)
    new.get_post(id)
  end

  def get_post(id)
    start_time = Time.now
    excon_response = connection.get(path: "/api/posts/#{id}/")
    duration = Time.now - start_time
    question = Question.new(data: JSON.parse(excon_response.body))
    Formatador.display_line(
      format(
        '[light_green](in %<minutes>dm %<seconds>ds)[/]',
        minutes: duration / 60, seconds: duration % 60
      )
    )
    question
  rescue Excon::Error => e
    puts e
    exit
  end

  private

  def connection
    @connection ||= Excon.new(
      'https://www.metaculus.com',
      expects: 200,
      headers: {
        'accept': 'application/json'
        # 'authorization': "Token #{ENV['METACULUS_API_TOKEN']}"
      }
    )
  end

  class Question
    attr_accessor :data

    def initialize(data:)
      @data = data
    end

    def background
      @background ||= data.dig('question', 'description')
    end

    def criteria
      @criteria ||= [data.dig('question', 'resolution_criteria'), data.dig('question', 'fine_print')].compact.join("\n\n").strip
    end

    def latest_count
      @latest_count ||= latest_aggregations['forecaster_count']
    end

    def latest_mean
      @latest_mean ||= (latest_aggregations['means'].first * 100).round
    end

    def latest_median
      @latest_median ||= (latest_aggregations['centers'].first * 100).round
    end

    def title
      @title ||= data.dig('question', 'title')
    end

    def to_json(*args)
      data.to_json(*args)
    end

    private

    def latest_aggregations
      @latest_aggregations ||= data.dig('question', 'aggregations', 'recency_weighted', 'latest')
    end
  end
end
