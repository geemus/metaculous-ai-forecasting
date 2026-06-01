# frozen_string_literal: true

require './lib/response'
require './lib/tools'

class Perplexity
  attr_accessor :model, :system, :temperature, :tools

  def initialize(
    model: 'sonar-reasoning-pro',
    system: RESEARCHER_SYSTEM_PROMPT,
    temperature: 0.1,
    tools: []
  )
    @model = model
    @system = system
    @temperature = temperature
    @tools = tools
  end

  # NOTE: If a forecaster-Perplexity is given the `search` tool, calling it
  # spawns a *second* Perplexity call (Tools.search instantiates its own
  # Perplexity with model `sonar-pro`, native web_search_options).  This
  # isn't infinite recursion but is an extra API round-trip.  For the
  # forecast path, Perplexity should be handed only `submit_forecast` (and
  # optionally `think`), **not** `search`.

  # https://docs.perplexity.ai/api-reference/chat-completions-post
  def eval(*messages)
    start_time = Time.now
    body = {
      model: model,
      messages: [
        {
          'role': 'system',
          'content': system
        }
      ].concat(messages),
      temperature: temperature
    }

    # Perplexity: native web_search_options and function-calling tools are
    # mutually exclusive.  Send tools only when non-empty; otherwise keep
    # the existing native search behavior for backward compatibility.
    if tools.empty?
      body[:web_search_options] = { search_context_size: 'medium' }
    else
      body[:tools] = tools
    end

    excon_response = connection.post(body: body.to_json)
    response = Response.new(
      :perplexity,
      duration: Time.now - start_time,
      json: excon_response.body
    )
    messages << {
      'role' => 'assistant',
      'content' => response.content,
      'reasoning_content' => response.reasoning_content
    }
    if response.tool_calls.empty?
      response.display_meta
      response
    else
      messages.last['tool_calls'] = response.tool_calls
      response.tool_calls.each do |tool_call|
        messages << {
          'content' => Tools.dispatch(tool_call),
          'role' => 'tool',
          'tool_call_id' => tool_call['id']
        }
      end

      self.eval(*messages)
    end
  rescue JSON::ParserError
    retries = (retries || 0) + 1
    retry if retries <= 3
    raise
  rescue Excon::Error => e
    puts e.message
    puts e.response.body
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
      idempotent: true,
      read_timeout: 600
    )
  end
end
