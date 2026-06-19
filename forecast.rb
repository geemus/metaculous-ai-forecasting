#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/script_helpers'

FORECASTERS = Provider::FORECASTERS

post_id = ARGV[0] || raise('post id argv[0] is required')
forecaster_index = ARGV[1]&.to_i || raise('forecaster index argv[1] is required')

question = fetch_question(post_id)
exit if should_skip_forecast?(question, post_id)

cache_write(post_id, 'inputs/system.superforecaster.md', SUPERFORECASTER_SYSTEM_PROMPT)
@research_output = load_research(post_id)

provider = FORECASTERS[forecaster_index]
Formatador.display "\n[bold][green]# Superforecaster[#{forecaster_index}: #{provider}]: Forecasting(#{post_id})…[/] "
cache(post_id, "forecasts/forecast.#{forecaster_index}.json") do
  # Perplexity Chat Completions doesn't support function calling (requires Agent API).
  # Use CALCULATOR_TOOL for providers that support it (OpenRouter/Anthropic, OpenAI, DeepSeek).
  tools = provider == :perplexity ? [] : [CALCULATOR_TOOL]
  llm_args = { system: SUPERFORECASTER_SYSTEM_PROMPT, temperature: 0.9, tools: tools }
  llm = Provider.new(provider, **llm_args)

  # Turn 1: forecast WITHOUT community aggregates (blind estimate)
  @include_aggregates = false
  forecast_prompt_blind = prompt_with_type(llm, question, SHARED_FORECAST_PROMPT_TEMPLATE)
  cache_write(post_id, "inputs/forecast.#{forecaster_index}.blind.md", forecast_prompt_blind)
  blind_response = llm.eval({ 'role': 'user', 'content': forecast_prompt_blind })
  cache_write(post_id, "outputs/forecast.#{forecaster_index}.blind.md", blind_response.content)

  # Turn 2: show aggregates and ask for revision (skip if no aggregates exist)
  final_response = if question.aggregate_content && !question.aggregate_content.empty?
                     aggregate_prompt = format(AGGREGATE_REVEAL_PROMPT, aggregate_content: question.aggregate_content)
                     cache_write(post_id, "inputs/forecast.#{forecaster_index}.aggregate.md", aggregate_prompt)
                     final = llm.eval(
                       { 'role': 'user', 'content': forecast_prompt_blind },
                       { 'role': 'assistant', 'content': blind_response.content },
                       { 'role': 'user', 'content': aggregate_prompt }
                     )
                     puts final.content
                     cache_write(post_id, "outputs/forecast.#{forecaster_index}.md", final.content)
                     final
                   else
                     puts blind_response.content
                     blind_response
                   end

  # Measure anchoring delta between blind and final estimate
  begin
    blind_parsed = Response.new(provider, json: blind_response.to_json)
    final_parsed = Response.new(provider, json: final_response.to_json)

    delta = case question.type
            when 'binary'
              blind_prob = blind_parsed.probability
              final_prob = final_parsed.probability
              (final_prob - blind_prob).abs
            when 'numeric', 'discrete'
              blind_p50 = blind_parsed.percentiles[50]
              final_p50 = final_parsed.percentiles[50]
              # Normalize by the full range for comparability across questions
              norm = question.upper_bound - question.lower_bound
              norm.positive? ? ((final_p50 - blind_p50).abs / norm) : 0.0
            when 'multiple_choice'
              blind_probs = blind_parsed.probabilities
              final_probs = final_parsed.probabilities
              common_keys = blind_probs.keys & final_probs.keys
              if common_keys.any?
                common_keys.sum { |k| (final_probs[k] - blind_probs[k]).abs } / common_keys.size.to_f
              else
                0.0
              end
            end

    cache_write(post_id, "forecasts/anchoring_delta.#{forecaster_index}.txt", delta.round(4).to_s)
  rescue StandardError => e
    warn "WARNING: failed to measure anchoring delta: #{e.message}"
  end

  final_response.to_json
end
