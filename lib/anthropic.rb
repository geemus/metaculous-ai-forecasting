# frozen_string_literal: true

class Anthropic
  attr_accessor :model, :system, :temperature

  def initialize(
    model: 'claude-sonnet-4-20250514',
    system: SUPERFORECASTER_SYSTEM_PROMPT,
    temperature: 0.1
  )
    @model = model
    @system = system
    @temperature = temperature
  end

  # https://docs.anthropic.com/en/api/messages
  def eval(*messages)
    start_time = Time.now
    excon_response = connection.post(
      body: {
        # model: 'claude-opus-4-1-20250805',
        model: model,
        max_tokens: 2048,
        messages: messages,
        system: system,
        temperature: temperature
      }.to_json
    )
    response = Response.new(
      duration: Time.now - start_time,
      data: JSON.parse(excon_response.body)
    )
    response.display_meta
    response
  rescue Excon::Error => e
    puts e
    exit(1)
  end

  private

  def connection
    Excon.new(
      'https://api.anthropic.com/v1/messages',
      expects: 200,
      headers: {
        'accept': 'application/json',
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
        'x-api-key': ENV['ANTHROPIC_API_KEY']
      },
      read_timeout: 360
    )
  end

  class Response
    attr_accessor :data, :duration

    def initialize(data:, duration: nil)
      @data = data
      @duration = duration
    end

    # NOTE: Anthropic API doesn't appear to return cost data
    def display_meta
      Formatador.display_line(
        format(
          '[light_green](%<total>d: %<input>d -> %<output>d tokens in %<minutes>dm %<seconds>ds)[/]',
          {
            total: total_tokens,
            input: input_tokens,
            output: output_tokens,
            minutes: duration / 60, seconds: duration % 60
          }
        )
      )
    end

    def content
      @content ||= begin
        text_array = data['content'].select { |content| content['type'] == 'text' }
        text_array.map { |content| content['text'] }.join("\n")
      end
    end

    def extracted_content(tag)
      extract_xml(tag, content)
    end

    def input_tokens
      @input_tokens ||= data['usage'].fetch_values('input_tokens', 'cache_creation_input_tokens', 'cache_read_input_tokens').sum
    end

    def output_tokens
      @output_tokens ||= data.dig('usage', 'output_tokens')
    end

    def percentiles
      @percentiles ||= begin
        percentiles = {}
        extracted_content('percentiles').split("\n").each do |line|
          key, value = line.split(': ', 2)
          key = key.split('Percentile ', 2).last
          value = value.split(' ', 2).first
          percentiles[key.to_i] = data.dig('question', 'scaling', 'continuous_range').first.is_a?(Float) ? value.to_f : value.to_i
        end
        percentiles
      end
    end

    def probabilities
      @probabilities ||= begin
        probabilities = {}
        extracted_content('probabilities').split("\n").each do |line|
          pair = line.split('Option "', 2).last
          key, value = pair.split('": ', 2)
          probabilities[key] = value.include?('%') ? value.to_f / 100.0 : value.to_f
        end
        probabilities
      end
    end

    def probability
      @probability ||= begin
        probability = extracted_content('probability')
        probability.include?('%') ? probability.to_f / 100.0 : probability.to_f
      end
    end

    def stripped_content(tag)
      strip_xml(tag, content)
    end

    def to_json(*args)
      data.to_json(*args)
    end

    def total_tokens
      @total_tokens ||= input_tokens + output_tokens
    end
  end
end
