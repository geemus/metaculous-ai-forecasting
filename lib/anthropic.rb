# frozen_string_literal: true

require './lib/helpers/response'

class Anthropic
  attr_accessor :model, :system, :temperature, :tools

  MAX_TOKENS = 8192

  def initialize(
    model: 'claude-sonnet-4-5',
    system: SUPERFORECASTER_SYSTEM_PROMPT,
    temperature: 0.1,
    tools: []
  )
    @model = model
    @system = system
    @temperature = temperature
    @tools = tools
  end

  # https://docs.anthropic.com/en/api/messages
  def eval(*messages)
    start_time = Time.now
    excon_response = connection.post(
      body: {
        # model: 'claude-opus-4-1-20250805',
        model: model,
        max_tokens: MAX_TOKENS,
        messages: messages,
        stream: false,
        system: system,
        temperature: temperature,
        tools: tools
      }.to_json
    )
    response = Response.new(
      duration: Time.now - start_time,
      json: excon_response.body
    )
    response.display_meta
    response
  rescue Excon::Error => e
    puts e
    puts e.response.body
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
    include ResponseHelpers

    attr_accessor :data, :duration

    def initialize(duration: nil, json: '{}')
      @data = JSON.parse(json)
      @duration = duration
    end

    def display_meta
      Formatador.display_line(
        format(
          '[light_green][anthropic](%<total>d: %<input>d -> %<output>d tokens in %<minutes>dm %<seconds>ds @ $%<cost>0.2f)[/]',
          {
            total: total_tokens,
            input: input_tokens,
            output: output_tokens,
            minutes: duration / 60, seconds: duration % 60,
            cost: cost
          }
        )
      )
      Formatador.display_line('[red]! TOKEN EXHAUSTION ![/]') if output_tokens >= MAX_TOKENS
    end

    def content
      @content ||= begin
        text_array = data['content'].select { |content| content['type'] == 'text' }
        text_array.map { |content| content['text'] }.join("\n")
      end
    end

    def cost
      @cost ||= begin
        # FIXME: this is sonnet pricing specifically, fwiw
        cost = 0
        cost += (input_tokens / 1_000_000.0) * 3.0 # $3/MTok
        cost += (output_tokens / 1_000_000.0) * 15.0 # $15/MTok
        cost.round(2)
      end
    end

    def input_tokens
      @input_tokens ||= data['usage'].fetch_values('input_tokens', 'cache_creation_input_tokens', 'cache_read_input_tokens').sum
    end

    def output_tokens
      @output_tokens ||= data.dig('usage', 'output_tokens')
    end

    def total_tokens
      @total_tokens ||= input_tokens + output_tokens
    end
  end
end
