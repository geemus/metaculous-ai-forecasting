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
        content << "Forecaster Count: #{latest_forecaster_count}"
        if type == 'multiple_choice'
          options.each_with_index do |option, index|
            content << format(
              'Option "%<option>s": { mean: %0.2<mean>f%%, lowest: %0.2<lowest>f%%, median: %0.2<median>f%%, highest: %0.2<highest>f%% }',
              {
                option: option,
                mean: latest_aggregations['means'][index] * 100,
                lowest: latest_aggregations['interval_lower_bounds'][index] * 100,
                median: latest_aggregations['centers'][index] * 100,
                highest: latest_aggregations['interval_upper_bounds'][index] * 100
              }
            )
          end
        else
          units_string = units.empty? ? '' : " #{units}"
          content << "Mean: #{latest_mean}#{units_string}" if latest_mean
          if %w[discrete numeric].include?(type) && scaling['open_lower_bound']
            below_lower_bound = (1 - latest_aggregations['forecast_values'].first) * 100
            content << format(
              'Below %<lower_bound>d: %<below_lower_bound>0.2f%%',
              below_lower_bound: below_lower_bound,
              lower_bound: lower_bound
            )
          end
          if type != 'binary' && latest_aggregations['interval_lower_bounds']
            lower_25_percent = (latest_aggregations['interval_lower_bounds'].first * upper_bound).round(2)
            content << "Lower 25%: #{lower_25_percent}#{units_string}"
          end
          content << "Median: #{latest_median}#{units_string}" if latest_median
          if type != 'binary' && latest_aggregations['interval_upper_bounds']
            upper_75_percent = (latest_aggregations['interval_upper_bounds'].first * upper_bound).round(2)
            content << "Upper 75%: #{upper_75_percent}#{units_string}"
          end
          if %w[discrete numeric].include?(type) && scaling['open_upper_bound']
            above_upper_bound = (1 - latest_aggregations['forecast_values'].last) * 100
            content << format(
              'Above %<upper_bound>d: %<above_upper_bound>0.2f%%',
              above_upper_bound: above_upper_bound,
              upper_bound: upper_bound
            )
          end
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

    def continuous_cdf(percentiles)
      x_values = cdf_xaxis
      y_values = []

      data = percentiles.dup

      # adjust any values exactly at bounds
      range_size = (scaling['range_max'] - scaling['range_min']).abs
      buffer = range_size > 100 ? 1 : 0.01 * range_size
      data.each do |key, value|
        if !scaling['open_lower_bound'] && value <= scaling['range_min'] + buffer
          data[key] = scaling['range_min'] + buffer
        end
        if !scaling['open_upper_bound'] && value >= scaling['range_max'] - buffer
          data[key] = scaling['range_max'] - buffer
        end
      end

      # set cdf values outside of range
      if scaling['open_lower_bound']
        if scaling['range_min'] < data[data.keys.min]
          data[(0.5 * data.keys.min).to_i] = scaling['range_min']
        end
      else
        data[0.0] = scaling['range_min']
      end
      if scaling['open_upper_bound']
        if scaling['range_max'] > data[data.keys.max]
          data[(100 - (0.5 * (100 - data.keys.max))).to_i] = scaling['range_max']
        end
      else
        data[100.0] = scaling['range_max']
      end

      # normalize percentiles
      normalized_percentiles = {}
      data.each do |key, value|
        normalized_percentiles[key.to_f / 100] = value
      end

      # swap to map specific values to probabilities
      data = normalized_percentiles.invert
      known_x = data.keys.sort

      x_values.each do |x|
        if known_x.include?(x)
          y_values.append(data[x])
        elsif x < known_x.first
          y_values.append(data[known_x.first])
        elsif x > known_x.last
          y_values.append(data[known_x.last])
        else
          previous_x = known_x.first
          next_x = known_x.last
          known_x.each do |kx|
            next_x = kx
            break if next_x > x

            previous_x = kx
          end
          previous_y = data[previous_x]
          next_y = data[next_x]

          y = previous_y + (x - previous_x) * (next_y - previous_y) / (next_x - previous_x)
          y_values.append(y)
        end
      end

      # standardize - see: https://www.metaculus.com/api/
      # - no mass outside closed bounds (scaling accordingly)
      # - at least minimum amount of mass outside open bounds
      # - increasing by at least minimum amount (0.01 / 200 = 0.0005)
      # - TODO: add smoothing for spiky CDFs (exceed change of 0.59)
      scale_lower_to = scaling['open_lower_bound'] ? 0.0 : y_values.first
      scale_upper_to = scaling['open_upper_bound'] ? 1.0 : y_values.last
      rescaled_inbound_mass = scale_upper_to - scale_lower_to

      y_values.each_with_index do |y, i|
        location = i / (y_values.length - 1)
        rescaled = (y - scale_lower_to) / rescaled_inbound_mass
        y_values[i] = if scaling['open_lower_bound'] && scaling['open_upper_bound']
                        0.988 * rescaled + 0.01 * location + 0.001
                      elsif scaling['open_lower_bound']
                        0.989 * rescaled + 0.01 * location + 0.001
                      elsif scaling['open_upper_bound']
                        0.989 * rescaled + 0.01 * location
                      else
                        0.99 * rescaled + 0.01 * location
                      end
      end
      # round to avoid floating point errors
      y_values.map! { |y| y.round(10) }

      y_values
    end

    def lower_bound
      @lower_bound ||= scaling['nominal_min'] || scaling['range_min']
    end

    def metadata_content
      @metadata_content ||= begin
        content = []
        unless lower_bound.nil?
          content << if scaling['open_lower_bound']
                       "Nominal Lower Bound: #{lower_bound}"
                     else
                       "Lower Bound: #{lower_bound}"
                     end
        end
        content << "Units: #{units}" unless units.empty?
        unless upper_bound.nil?
          content << if scaling['open_upper_bound']
                       "Nominal Upper Bound: #{upper_bound}"
                     else
                       "Upper Bound: #{upper_bound}"
                     end
        end
        content.join("\n")
      end
    end

    def options
      @options ||= question['options']
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

    def cdf_xaxis
      @cdf_xaxis ||= scaling['continuous_range']
    end

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
