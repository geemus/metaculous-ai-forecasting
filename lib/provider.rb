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

  class << self
    # Factory method to instantiate a provider
    # Usage: Provider.new(:anthropic, **args)
    def new(provider_symbol, **args)
      klass = PROVIDER_CLASSES[provider_symbol]
      raise ArgumentError, "Unknown provider: #{provider_symbol}" unless klass

      case provider_symbol
      when :anthropic
        args[:model] ||= 'anthropic/claude-opus-4.5'
      when :openai
        args[:model] ||= 'openai/gpt-5.2'
      end

      klass.new(**args)
    end
  end
end
