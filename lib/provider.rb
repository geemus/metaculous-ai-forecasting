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
    openai
    perplexity
    deepseek
  ].freeze

  # Map provider symbols to their class names
  PROVIDER_CLASSES = {
    anthropic: OpenRouter,
    perplexity: Perplexity,
    deepseek: DeepSeek,
    openai: OpenRouter
  }.freeze

  DEFAULT_MODELS = {
    anthropic: 'anthropic/claude-opus-4.6',
    openai: 'openai/gpt-5.4'
  }.freeze

  class << self
    # Factory method to instantiate a provider
    # Usage: Provider.new(:anthropic, **args)
    def new(provider_symbol, **args)
      klass = PROVIDER_CLASSES[provider_symbol]
      raise ArgumentError, "Unknown provider: #{provider_symbol}" unless klass

      args[:model] ||= DEFAULT_MODELS[provider_symbol] if DEFAULT_MODELS.key?(provider_symbol)

      klass.new(**args)
    end
  end
end
