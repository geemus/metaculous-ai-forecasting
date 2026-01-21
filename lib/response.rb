# frozen_string_literal: true

require './lib/helpers/response'

class Response
  include ResponseHelpers

  attr_accessor :data, :duration, :provider

  def initialize(provider, duration: nil, json: '{}')
    @provider = provider.to_sym
    @data = JSON.parse(json)
    @duration = duration
  end

  def display_meta
    Formatador.display_line(
      format(
        "[light_green][#{provider}](%<total>d: %<input>d -> %<output>d tokens in %<minutes>dm %<seconds>ds @ $%<cost>0.2f)[/]",
        {
          total: total_tokens,
          input: input_tokens,
          output: output_tokens,
          minutes: duration_minutes,
          seconds: duration_seconds,
          cost: cost
        }
      )
    )
    Formatador.display_line('[red]! TOKEN EXHAUSTION ![/]') if token_exhaustion?
  end

  def content
    @content ||= case provider
                 # when :anthropic
                 #   anthropic_content
                 when :deepseek, :perplexity, :openai, :open_router, :anthropic
                   openai_compatible_content
                 else
                   raise "Unknown provider: #{provider}"
                 end
  end

  def reasoning_content
    @reasoning_content ||= case provider
                           # when :anthropic
                           #   anthropic_reasoning_content
                           when :deepseek, :perplexity, :openai, :open_router, :anthropic
                             openai_compatible_reasoning_content
                           else
                             raise "Unknown provider: #{provider}"
                           end
  end

  def tool_calls
    @tool_calls ||= case provider
                    # when :anthropic
                    #   anthropic_tool_calls
                    when :deepseek, :perplexity, :openai, :open_router, :anthropic
                      openai_compatible_tool_calls
                    else
                      raise "Unknown provider: #{provider}"
                    end
  end

  def cost
    @cost ||= case provider
              # when :anthropic
                # anthropic_cost
              when :deepseek
                deepseek_cost
              when :perplexity
                perplexity_cost
              when :open_router, :anthropic, :openai
                open_router_cost
              # when :openai
              #   openai_cost
              else
                0.0
              end
  end

  def input_tokens
    @input_tokens ||= case provider
                      # when :anthropic
                        # anthropic_input_tokens
                      when :perplexity, :deepseek, :openai, :open_router, :anthropic
                        data.dig('usage', 'prompt_tokens') || 0
                      else
                        0
                      end
  end

  def output_tokens
    @output_tokens ||= case provider
                       # when :anthropic
                       #   data.dig('usage', 'output_tokens') || 0
                       when :perplexity
                         perplexity_output_tokens
                       when :deepseek, :openai, :open_router, :anthropic
                         data.dig('usage', 'completion_tokens') || 0
                       else
                         0
                       end
  end

  def total_tokens
    @total_tokens ||= case provider
                      # when :anthropic
                      #   input_tokens + output_tokens
                      when :perplexity, :deepseek, :openai, :open_router, :anthropic
                        data.dig('usage', 'total_tokens') || (input_tokens + output_tokens)
                      else
                        0
                      end
  end

  private

  def duration_minutes
    duration ? duration / 60 : 0
  end

  def duration_seconds
    duration ? duration % 60 : 0
  end

  def token_exhaustion?
    # provider == :anthropic && output_tokens >= 8192
    false
  end

  # Anthropic-specific methods
  def anthropic_content
    text_array = data['content'].select { |content| content['type'] == 'text' }
    text_array.map { |content| content['text'] }.join("\n")
  end

  def anthropic_cost
    cost = 0
    cost += (input_tokens / 1_000_000.0) * 3.0   # $3/MTok
    cost += (output_tokens / 1_000_000.0) * 15.0 # $15/MTok
    cost.round(2)
  end

  def anthropic_input_tokens
    data['usage'].fetch_values('input_tokens', 'cache_creation_input_tokens', 'cache_read_input_tokens').sum
  rescue
    data.dig('usage', 'input_tokens') || 0
  end

  def anthropic_reasoning_content
    data['content'].select { |content| content['type'] == 'thinking' }
  end

  def anthropic_tool_calls
    data['content'].select { |content| content['type'] == 'tool_use' }
  end

  def open_router_cost
    (data.dig('usage', 'cost') || 0) + (data.dig('usage', 'cost_details')&.values&.compact&.sum || 0)
  end

  # OpenAI-compatible content (used by Perplexity, DeepSeek, OpenAI)
  def openai_compatible_content
    data['choices'].map { |choice| choice['message']['content'] }.join("\n")
  end

  # OpenAI-compatible reasoning content (used by Perplexity, DeepSeek, OpenAI)
  def openai_compatible_reasoning_content
    reasoning_content = data['choices'].map { |choice| choice['message']['content'] }
    reasoning_content.join("\n")
  end

  # OpenAI-compatible tool_calls (used by Perplexity, DeepSeek, OpenAI)
  def openai_compatible_tool_calls
    data['choices'].map { |choice| choice['message']['tool_calls'] }.flatten.compact
  end

  # DeepSeek-specific methods
  def deepseek_cost
    cost = 0
    cost += (data.dig('usage', 'prompt_cache_hit_tokens') || 0) / 1_000_000.0 * 0.028  # $0.028/MTok
    cost += (data.dig('usage', 'prompt_cache_miss_tokens') || 0) / 1_000_000.0 * 0.28  # $0.28/MTok
    cost += (output_tokens / 1_000_000.0) * 0.42 # $0.42/MTok
    cost.round(2)
  end

  # Perplexity-specific methods
  def perplexity_cost
    data.dig('usage', 'cost', 'total_cost') || 0.0
  end

  def perplexity_output_tokens
    total = data.dig('usage', 'total_tokens') || 0
    prompt = data.dig('usage', 'prompt_tokens') || 0
    total - prompt
  end

  # OpenAI-specific methods (placeholder)
  def openai_cost
    # TODO: Implement OpenAI cost calculation
    0.0
  end
end
