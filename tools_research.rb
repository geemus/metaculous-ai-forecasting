#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/script_helpers'

post_id = ARGV[0] || raise('post id argument is required')

question = fetch_question(post_id)
exit if should_skip_forecast?(question, post_id)

cache_write(post_id, 'inputs/system.researcher.md', RESEARCHER_SYSTEM_PROMPT)

@news_output = load_cached_news(post_id)

cache(post_id, 'research.json') do
  Formatador.display "\n[bold][green]# Researcher: Researching(#{post_id})…[/] "

  @forecast_prompt = FORECAST_PROMPT_TEMPLATE.result(binding)
  @research_prompt = RESEARCH_PROMPT_TEMPLATE.result(binding)
  cache_write(post_id, 'inputs/research.md', @research_prompt)

  start_time = Time.now

  begin
    # Perplexity Agent API with native web_search + custom calculate tool.
    # Eliminates the OpenRouter→Perplexity Chat Completions double-hop:
    # the Agent API runs web_search internally, and only pauses for
    # calculate function calls that we execute locally.
    #
    # IMPORTANT: the Agent API is stateless — every HTTP request is
    # independent.  For multi-turn function calling we accumulate all
    # prior input items (user message, function_call items, and
    # function_call_output items) and replay them on each follow-up
    # call so the model retains full conversation context.
    agent = Excon.new(
      'https://api.perplexity.ai/v1/agent',
      expects: 200,
      headers: {
        'accept': 'application/json',
        'authorization': "Bearer #{ENV['PERPLEXITY_API_KEY']}",
        'content-type': 'application/json'
      },
      idempotent: true,
      read_timeout: 600
    )

    agent_tools = [
      { type: 'web_search' },
      { type: 'finance_search' },
      { type: 'fetch_url' },
      {
        type: 'function',
        name: 'calculate',
        description: CALCULATOR_TOOL[:function][:description],
        parameters: CALCULATOR_TOOL[:function][:parameters]
      }
    ]

    # Accumulated input items replayed on every follow-up so the
    # stateless Agent API retains full conversation context.
    input_items = [{ type: 'message', role: 'user', content: @research_prompt }]

    # Track tool invocations across all requests for a single summary.
    total_tally = Hash.new(0)

    response = JSON.parse(
      agent.post(body: {
        model: 'anthropic/claude-opus-5',
        max_output_tokens: 8192,
        max_steps: 10,
        tool_choice: 'auto',
        input: input_items,
        instructions: RESEARCHER_SYSTEM_PROMPT,
        tools: agent_tools
      }.to_json).body
    )

    response['output'].map { |item| item['type'] }.tally.each { |type, count| total_tally[type] += count }

    # Handle custom function_call loop — web_search is handled natively by
    # Perplexity's runtime and never appears as a function_call here.
    loop do
      function_calls = response['output'].select { |item| item['type'] == 'function_call' }
      break if function_calls.empty?

      # Append the model's function_call items to input history.
      input_items.concat(function_calls)

      function_outputs = function_calls.map do |fc|
        arguments = JSON.parse(fc['arguments'])
        result = case fc['name']
                 when 'calculate'
                   Tools.calculate(arguments)
                 else
                   raise "Unknown function: #{fc['name']}"
                 end
        { type: 'function_call_output', call_id: fc['call_id'], output: result }
      end

      # Append function results to input history.
      input_items.concat(function_outputs)

      # Replay full input history so the model retains context about
      # the original research question and prior function calls.
      response = JSON.parse(
        agent.post(body: {
          model: 'anthropic/claude-opus-5',
          max_output_tokens: 8192,
          max_steps: 10,
          tool_choice: 'auto',
          input: input_items,
          instructions: RESEARCHER_SYSTEM_PROMPT,
          tools: agent_tools
        }.to_json).body
      )

      response['output'].map { |item| item['type'] }.tally.each { |type, count| total_tally[type] += count }
    end

    summary = total_tally.map { |type, count| "#{type}×#{count}" }.sort.join(', ')
    Formatador.display_line "\n# Researcher: #{summary}"

    # Extract text content from the Agent API response.
    # Content may be a plain string or an array of {type, text} blocks,
    # depending on whether web search results were included.
    text = response['output']
      .select { |item| item['role'] == 'assistant' }
      .map { |item| item['content'] }
      .flatten
      .map { |c| c.is_a?(Hash) ? c['text'] : c }
      .compact
      .join("\n")

    cache_write(post_id, 'outputs/research.md', text)

    duration = Time.now - start_time
    Formatador.display_line(
      format(
        "[light_green][perplexity_agent](%<total>d tokens in %<minutes>dm %<seconds>ds)[/]",
        {
          total: response.dig('usage', 'total_tokens') || 0,
          minutes: (duration / 60).to_i,
          seconds: (duration % 60).to_i
        }
      )
    )

    # Transform to OpenAI-compatible shape so downstream consumers
    # (load_research → Response.new(:open_router, …)) parse unchanged.
    openai_compatible = {
      'choices' => [
        {
          'message' => {
            'content' => text,
            'role' => 'assistant'
          },
          'finish_reason' => 'stop'
        }
      ],
      'usage' => {
        'prompt_tokens' => response.dig('usage', 'input_tokens') || 0,
        'completion_tokens' => response.dig('usage', 'output_tokens') || 0,
        'total_tokens' => response.dig('usage', 'total_tokens') || 0
      },
      'model' => response['model'] || 'anthropic/claude-opus-5'
    }

    JSON.pretty_generate(openai_compatible)
  rescue JSON::ParserError
    retries = (retries || 0) + 1
    retry if retries <= 3
    raise
  rescue Excon::Error => e
    puts e.message
    puts e.response.body
    exit(1)
  end
end
