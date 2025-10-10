# frozen_string_literal: true

require './lib/helpers/response'

class DeepSeek
  attr_accessor :model, :system, :temperature

  def initialize(
    model: 'deepseek-reasoner',
    system: SUPERFORECASTER_SYSTEM_PROMPT,
    temperature: 0.1
  )
    @model = model
    @system = system
    @temperature = temperature
  end

  # https://api-docs.deepseek.com/api/create-chat-completion
  def eval(*messages)
    start_time = Time.now
    excon_response = connection.post(
      body: {
        # max_tokens: 2048,
        model: model,
        messages: [
          {
            'role': 'system',
            'content': system
          }
        ].concat(messages),
        temperature: temperature
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
    exit(1)
  end

  private

  def connection
    Excon.new(
      'https://api.deepseek.com/chat/completions',
      expects: 200,
      headers: {
        'accept': 'application/json',
        'authorization': "Bearer #{ENV['DEEPSEEK_API_KEY']}",
        'content-type': 'application/json'
      },
      read_timeout: 600
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
          '[light_green][deepseek](%<total>d: %<input>d -> %<output>d tokens in %<minutes>dm %<seconds>ds @ $%<cost>0.2f)[/]',
          {
            total: total_tokens,
            input: input_tokens,
            output: output_tokens,
            minutes: @duration / 60,
            seconds: @duration % 60,
            cost: cost
          }
        )
      )
    end

    def content
      @content ||= data['choices'].map { |choice| choice['message']['content'] }.join("\n")
    end

    def cost
      @cost ||= begin
        cost = 0
        cost += (data.dig('usage', 'prompt_cache_hit_tokens') / 1_000_000.0) * 0.028 # $0.028/MTok
        cost += (data.dig('usage', 'prompt_cache_miss_tokens') / 1_000_000.0) * 0.28 # $0.28/MTok
        cost += (output_tokens / 1_000_000.0) * 0.42 # $0.42/MTok
        cost
      end
    end

    def input_tokens
      @input_tokens ||= data.dig('usage', 'prompt_tokens')
    end

    def output_tokens
      @output_tokens ||= data.dig('usage', 'completion_tokens')
    end

    def total_tokens
      @total_tokens ||= data.dig('usage', 'total_tokens')
    end
  end
end
