# frozen_string_literal: true

require './lib/anthropic'
require './lib/deepseek'
require './lib/open_router'
require './lib/openai'
require './lib/perplexity'

module Provider
  # Forecasters list
  FORECASTERS = %i[
    anthropic
    perplexity
    deepseek
  ].freeze

  # Map provider symbols to their class names
  PROVIDER_CLASSES = {
    anthropic: Anthropic,
    perplexity: Perplexity,
    deepseek: DeepSeek,
    openai: OpenAI
  }.freeze

  class << self
    # Factory method to instantiate a provider
    # Usage: Provider.new(:anthropic, **args)
    def new(provider_symbol, **args)
      klass = PROVIDER_CLASSES[provider_symbol]
      raise ArgumentError, "Unknown provider: #{provider_symbol}" unless klass

      klass.new(**args)
    end
  end
end
