# frozen_string_literal: true

require './lib/response'

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
      :anthropic,
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
end
