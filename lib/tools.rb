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
