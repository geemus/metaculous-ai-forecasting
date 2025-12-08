# frozen_string_literal: true

require './lib/response'

SEARCH_TOOL = {
  type: 'function',
  function: {
    name: 'search',
    description: 'Search the web for the latest information.',
    parameters: {
      type: 'object',
      properties: {
        'prompt': {
          type: 'string',
          description: 'Full sentences or paragraphs to prompt web search with context and instructions.'
        }
      }
    },
    required: ['prompt']
  }
}.freeze

class DeepSeek
  attr_accessor :model, :system, :temperature, :tools

  def initialize(
    model: 'deepseek-reasoner',
    system: SUPERFORECASTER_SYSTEM_PROMPT,
    temperature: 0.1,
    tools: []
  )
    @model = model
    @system = system
    @temperature = temperature
    @tools = tools
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
        temperature: temperature,
        tools: tools
      }.to_json
    )
    data = JSON.parse(excon_response.body)
    content = data['choices'].map { |choice| choice['message']['content'] }.join("\n")
    tool_calls = data['choices'].map { |choice| choice['message']['tool_calls'] }.flatten.compact
    messages << {
      'role' => 'assistant',
      'content' => content
    }
    response = Response.new(
      :deepseek,
      duration: Time.now - start_time,
      json: excon_response.body
    )
    if tool_calls.empty?
      response.display_meta
      response
    else
      messages.last['tool_calls'] = tool_calls
      tool_calls.each do |tool_call|
        arguments = JSON.parse(tool_call.dig('function', 'arguments'))
        tool = tool_call.dig('function', 'name')
        result = case tool
                 when 'search'
                   tool_search(arguments)
                 else
                   raise "Unknown Tool Requested: `#{tool}`"
                 end

        messages << {
          'content' => result.content,
          'role' => 'tool',
          'tool_call_id' => tool_call['id']
        }
      end

      self.eval(*messages)
    end
  rescue Excon::Error => e
    puts e
    puts e.request[:body]
    puts e.response.body
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
      idempotent: true,
      read_timeout: 600
    )
  end

  def tool_search(arguments)
    prompt = arguments['prompt']
    Formatador.display "\n[bold][green]# Researcher: Searching([faint]#{prompt}[/])…[/] "

    llm = Perplexity.new(system: <<~SYSTEM)
      You are an experienced research assistant for a superforecaster.

      # Guidance
      - Prioritize clarity and conciseness.
      - Generate research summaries that are concise while retaining necessary detail.
    SYSTEM
    llm.eval(
      { 'role': 'user', 'content': prompt }
    )
  end
end
