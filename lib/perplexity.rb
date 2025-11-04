# frozen_string_literal: true

require './lib/response'

class Perplexity
  attr_accessor :model, :system, :temperature

  def initialize(
    model: 'sonar',
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
      :perplexity,
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
end
