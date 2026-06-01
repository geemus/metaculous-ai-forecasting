# frozen_string_literal: true

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
      - Include date context (e.g. "as of 2025") for time-sensitive topics.

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
      }
    },
    required: ['prompt']
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

    # Shared tool-call dispatch.  Used by all tool-capable clients
    # (OpenRouter, DeepSeek, Perplexity) so that tool routing stays in
    # one place — especially important as #120 adds `submit_forecast`.
    def dispatch(tool_call)
      arguments = JSON.parse(tool_call.dig('function', 'arguments'))
      tool = tool_call.dig('function', 'name')
      case tool
      when 'search'
        search(arguments).content
      else
        raise "Unknown Tool Requested: `#{tool}`"
      end
    end
  end
end
