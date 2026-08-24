# frozen_string_literal: true

require './lib/deepseek'
require './lib/open_router'

module Provider
  # Forecasters list
  FORECASTERS = %i[
    anthropic
    openai
    gemini
    deepseek
  ].freeze

  # Map provider symbols to their class names
  PROVIDER_CLASSES = {
    anthropic: OpenRouter,
    gemini: OpenRouter,
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
        args[:model] ||= 'anthropic/claude-opus-5'
      when :gemini
        args[:model] ||= 'google/gemini-2.5-pro'
      when :openai
        args[:model] ||= 'openai/gpt-5.6-sol'
        args[:api_key] ||= ENV['OPEN_ROUTER_OPENAI_API_KEY'] || ENV['OPEN_ROUTER_API_KEY']
      end

      klass.new(**args)
    end
  end
end
