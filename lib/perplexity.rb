# frozen_string_literal: true

require './lib/helpers/response'

class Perplexity
  attr_accessor :model, :system, :temperature

  def initialize(
    model: 'sonar-reasoning',
    system: RESEARCHER_SYSTEM_PROMPT,
    temperature: 0.1
  )
    @model = model
    @system = system
    @temperature = temperature
  end

  # https://docs.perplexity.ai/api-reference/chat-completions-post
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
        temperature: temperature,
        web_search_options: {
          search_context_size: 'medium'
        }
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
      'https://api.perplexity.ai/chat/completions',
      expects: 200,
      headers: {
        'accept': 'application/json',
        'authorization': "Bearer #{ENV['PERPLEXITY_API_KEY']}",
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
          '[light_green][perplexity](%<total>d: %<input>d -> %<output>d tokens in %<minutes>dm %<seconds>ds @ $%<cost>0.2f)[/]',
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
      @data.dig('usage', 'cost', 'total_cost')
    end

    def input_tokens
      @input_tokens ||= data.dig('usage', 'prompt_tokens')
    end

    def output_tokens
      @output_tokens ||= data.dig('usage', 'total_tokens') - data.dig('usage', 'prompt_tokens')
    end

    def total_tokens
      @total_tokens ||= data.dig('usage', 'total_tokens')
    end
  end
end
