# frozen_string_literal: true

SEARCH_TOOL = {
  type: 'function',
  function: {
    name: 'search',
    description: <<~DESCRIPTION,
      Search for public information related to a particular prompt.

      # Usage
      - Provides access to information that is newer than or missing from training data.

      # Relevance
      - Use for current events, recent developments, or missing information.
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

THINK_TOOL = {
  type: 'function',
  function: {
    name: 'think',
    description: <<~DESCRIPTION,
      Think out loud, take notes, form plans.

      # Usage
      - Has no external effects.

      # Relevance
      - Skip for trivial single-step tasks.
    DESCRIPTION
    parameters: {
      type: 'object',
      properties: {
        thoughts: {
          type: 'string',
          description: 'The thoughts, notes, or plans.'
        }
      }
    }
  }
}.freeze

module Tools
  class << self
    def search(arguments)
      prompt = arguments['prompt']
      Formatador.display "\n[bold][green]# Researcher: Searching[faint](#{prompt})[/]…[/] "

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

    def think(arguments)
      thoughts = arguments['thoughts']
      Formatador.display_line "\n[bold][green]Thinking[faint](#{thoughts})[/]"
      'Thought thoughts.'
    end
  end
end
