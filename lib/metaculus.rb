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

    def aggregate_content
      @aggregate_content ||= begin
        content = []
        content << "<forecaster-count>#{latest_forecaster_count}</forecaster-count>"
        content << "<mean>#{latest_mean}</mean>" if latest_mean
        if %w[discrete numeric].include?(type) && scaling['open_lower_bound']
          below_lower_bound = (1 - latest_aggregations['forecast_values'].first) * 100
          content << format(
            '<below_%<lower_bound>d>%<below_lower_bound>0.2f%%</below_%<lower_bound>d>',
            below_lower_bound: below_lower_bound,
            lower_bound: lower_bound
          )
        end
        if !type != 'binary' && latest_aggregations['interval_lower_bounds']
          lower_25_percent = (latest_aggregations['interval_lower_bounds'].first * upper_bound).round(2)
          content << "<lower_25_percent>#{lower_25_percent}</lower_25_percent>"
        end
        content << "<median>#{latest_median}</median>" if latest_median
        if type != 'binary' && latest_aggregations['interval_upper_bounds']
          upper_75_percent = (latest_aggregations['interval_upper_bounds'].first * upper_bound).round(2)
          content << "<upper_75_percent>#{upper_75_percent}</upper_75_percent>"
        end
        if %w[discrete numeric].include?(type) && scaling['open_upper_bound']
          above_upper_bound = (1 - latest_aggregations['forecast_values'].last) * 100
          content << format(
            '<above_%<upper_bound>d>%<above_upper_bound>0.2f%%</above_%<upper_bound>d>',
            above_upper_bound: above_upper_bound,
            upper_bound: upper_bound
          )
        end
        content.join("\n")
      end
    end

    def background
      @background ||= question['description']
    end

    def criteria_content
      @criteria_content ||= [question['resolution_criteria'], question['fine_print']].compact.join("\n\n").strip
    end

    def latest_forecaster_count
      @latest_forecaster_count ||= latest_aggregations['forecaster_count']
    end

    def latest_mean
      @latest_mean ||= latest_aggregations['means'] && (latest_aggregations['means'].first * 100).round
    end

    def latest_median
      @latest_median ||= case type
                         when 'binary'
                           format('%0.2f%%', latest_aggregations['centers'].first * 100)
                         when 'multiple_choice'
                           # TODO: implement
                         else
                           (latest_aggregations['centers'].first * upper_bound).round(2)
                         end
    end

    def lower_bound
      @lower_bound ||= scaling['nominal_min'] || scaling['range_min']
    end

    def metadata_content
      @metadata_content ||= begin
        content = []
        unless lower_bound.nil?
          content << if scaling['open_lower_bound']
                       "<nominal_lower_bound>#{lower_bound}</nominal_lower_bound>"
                     else
                       "<lower_bound>#{lower_bound}</lower_bound>"
                     end
        end
        content << "<units>#{units}</units>" unless units.empty?
        unless upper_bound.nil?
          content << if scaling['open_upper_bound']
                       "<nominal_upper_bound>#{upper_bound}</nominal_upper_bound>"
                     else
                       "<upper_bound>#{upper_bound}</upper_bound>"
                     end
        end
        content.join("\n")
      end
    end

    def title
      @title ||= question['title']
    end

    def type
      @type ||= question['type']
    end

    def units
      @units ||= question['unit']
    end

    def upper_bound
      @upper_bound ||= scaling['nominal_max'] || scaling['range_max']
    end

    def to_json(*args)
      data.to_json(*args)
    end

    private

    def latest_aggregations
      @latest_aggregations ||= data.dig('question', 'aggregations', 'recency_weighted', 'latest')
    end

    def question
      @question ||= data['question']
    end

    def scaling
      @scaling ||= data.dig('question', 'scaling')
    end
  end
end
