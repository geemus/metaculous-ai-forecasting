# frozen_string_literal: true

require_relative 'calculator'

SEARCH_TOOL = {
  type: 'function',
  function: {
    name: 'search',
    description: <<~DESCRIPTION,
      Search for public information related to a particular prompt.

      # Usage
      - Provides access to information that is newer than or missing from training data.
      - Decompose complex questions into focused sub-queries for better results.
      - Prefer specific, targeted queries over broad ones.

      # Time-Sensitive Queries
      - Always include the current month and year in queries for time-sensitive topics (e.g. "July 2026 US Drought Monitor latest observed reading").
      - When you need current conditions, explicitly request "observed," "measured," "latest reading," or "actual" data — not forecasts or projections.
      - If a search returns a projection or forecast, follow up with a second search specifically for the most recent actual measurement.
      - Prefer direct data sources (government monitoring, exchange data, official statistics) over news summaries that may reference older data.

      # Relevance
      - Use for current events, recent developments, or missing information.
      - Use when base rates or historical frequencies are unknown.
      - Use to verify claims or check for contradicting evidence.
    DESCRIPTION
    parameters: {
      type: 'object',
      properties: {
        prompt: {
          type: 'string',
          description: 'Full sentences or paragraphs to prompt web search with context and instructions.'
        }
      },
      required: ['prompt']
    }
  }
}.freeze

CALCULATOR_TOOL = {
  type: 'function',
  function: {
    name: 'calculate',
    description: <<~DESCRIPTION,
      Evaluate an arithmetic expression safely and return the result.

      # Usage
      - Use for any computation with more than two numbers or more than one operation.
      - Use for percentage math, compounding, expected values, Bayes updates.
      - Use when precision matters (e.g. normalization, log-odds conversion).
      - Prefer a single expression; chain via multiple calls if needed.

      # Supported
      - Operators: +, -, *, /, ^ (exponentiation), % (modulo)
      - Functions: SQRT, LOG, LOG10, LOG2, EXP, ABS, ROUND(n), ROUNDDOWN, ROUNDUP
      - Constants: PI, E
      - Grouping: parentheses
      - Functions are case-insensitive (round, ROUND, Round all work).

      # Examples
      - "0.35 * 0.8 + 0.65 * 0.2"
      - "LOG(0.5 / 0.5)"
      - "100 * (1.02 ^ 5)"
      - "SQRT(0.3 * 0.7 / 100)"
      - "ROUND(42.6789, 2)"
    DESCRIPTION
    parameters: {
      type: 'object',
      properties: {
        expression: {
          type: 'string',
          description: 'The arithmetic expression to evaluate (e.g. "0.35 * 0.8 + 0.65 * 0.2").'
        }
      },
      required: ['expression']
    }
  }
}.freeze

module Tools
  class << self
    def search(arguments)
      prompt = arguments['prompt']
      Formatador.display "\n[bold][green]# Researcher: Searching[faint](#{prompt})[/]…[/] "

      llm = Perplexity.new(
        model: 'sonar-pro',
        system: <<~SYSTEM)
          You are an experienced research assistant for a superforecaster.

          # Guidance
          - Prioritize clarity and conciseness.
          - Generate research summaries that are concise while retaining necessary detail.
        SYSTEM
      llm.eval(
        { 'role': 'user', 'content': prompt }
      )
    end

    def calculate(arguments)
      expression = arguments['expression']
      result = Calculator.evaluate(expression)
      result.to_s
    end

    # Shared tool-call dispatch.  Used by all tool-capable clients
    # (OpenRouter, DeepSeek, Perplexity) so that tool routing stays in
    # one place — especially important as #120 adds `submit_forecast`.
    def dispatch(tool_call)
      arguments = JSON.parse(tool_call.dig('function', 'arguments'))
      tool = tool_call.dig('function', 'name')
      case tool
      when 'search'
        search(arguments).content
      when 'calculate'
        calculate(arguments)
      else
        raise "Unknown Tool Requested: `#{tool}`"
      end
    end
  end
end
