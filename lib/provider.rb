# frozen_string_literal: true

require './lib/deepseek'
require './lib/open_router'
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
        args[:model] ||= 'anthropic/claude-sonnet-4.5'
      when :openai
        args[:model] ||= 'openai/gpt-4.1-mini'
        args[:api_key] ||= ENV['OPEN_ROUTER_OPENAI_API_KEY'] || ENV['OPEN_ROUTER_API_KEY']
      end

      klass.new(**args)
    end
  end
end
