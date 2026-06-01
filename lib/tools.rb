# frozen_string_literal: true

require_relative 'calculator'

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
      },
      required: ['prompt']
    }
  }
}.freeze

CALCULATOR_TOOL = {
  type: 'function',
  function: {
    name: 'calculate',
    description: <<~DESCRIPTION,
      Evaluate an arithmetic expression safely and return the result.

      # Usage
      - Use for any computation with more than two numbers or more than one operation.
      - Use for percentage math, compounding, expected values, Bayes updates.
      - Use when precision matters (e.g. normalization, log-odds conversion).
      - Prefer a single expression; chain via multiple calls if needed.

      # Supported
      - Operators: +, -, *, /, ^ (exponentiation), % (modulo)
      - Functions: SQRT, LOG, LOG10, LOG2, EXP, ABS, ROUND(n), ROUNDDOWN, ROUNDUP
      - Constants: PI, E
      - Grouping: parentheses
      - Functions are case-insensitive (round, ROUND, Round all work).

      # Examples
      - "0.35 * 0.8 + 0.65 * 0.2"
      - "LOG(0.5 / 0.5)"
      - "100 * (1.02 ^ 5)"
      - "SQRT(0.3 * 0.7 / 100)"
      - "ROUND(42.6789, 2)"
    DESCRIPTION
    parameters: {
      type: 'object',
      properties: {
        expression: {
          type: 'string',
          description: 'The arithmetic expression to evaluate (e.g. "0.35 * 0.8 + 0.65 * 0.2").'
        }
      },
      required: ['expression']
    }
  }
}.freeze

BAYESIAN_UPDATE_TOOL = {
  type: 'function',
  function: {
    name: 'bayesian_update',
    description: <<~DESCRIPTION,
      Compute an exact posterior probability from a prior and one or more likelihood ratios. Use this whenever you adjust a base rate with evidence — it is more accurate than mental arithmetic.

      # Two modes for expressing evidence (you can use either or both together)

      ## Mode A: Direct likelihood ratio (simpler, preferred)
      Provide `likelihood_ratios` as an array of numbers. Each ratio is P(E|H)/P(E|¬H).
      Values > 1 support the hypothesis; values < 1 oppose it; 1 is neutral.
      Multiple ratios are multiplied together (assumes independent evidence).

      ## Mode B: Component probabilities
      Provide `evidence_items` as an array of objects, each with `p_e_given_h` (P(E|H))
      and `p_e_given_not_h` (P(E|¬H)). The tool computes LR = P(E|H)/P(E|¬H) for each.

      # Examples
      - Single supporting evidence: prior=0.2, likelihood_ratios=[3] → posterior≈0.429
      - Multiple evidence: prior=0.1, likelihood_ratios=[5, 2] → posterior≈0.526
      - Opposing evidence: prior=0.5, likelihood_ratios=[0.25] → posterior=0.2
      - Component mode: prior=0.3, evidence_items=[{p_e_given_h: 0.8, p_e_given_not_h: 0.2}] → LR=4, posterior≈0.632
    DESCRIPTION
    parameters: {
      type: 'object',
      properties: {
        prior: {
          type: 'number',
          description: 'Prior probability as a decimal between 0 and 1 (e.g. 0.15 for 15%).'
        },
        likelihood_ratios: {
          type: 'array',
          items: { type: 'number' },
          description: 'One or more likelihood ratios P(E|H)/P(E|¬H). Values > 1 support the hypothesis; values < 1 oppose it; 1 is neutral. Multiply independent ratios together.'
        },
        evidence_items: {
          type: 'array',
          items: {
            type: 'object',
            properties: {
              p_e_given_h: {
                type: 'number',
                description: 'Probability of observing this evidence if the hypothesis is true.'
              },
              p_e_given_not_h: {
                type: 'number',
                description: 'Probability of observing this evidence if the hypothesis is false.'
              }
            },
            required: ['p_e_given_h', 'p_e_given_not_h']
          },
          description: "Alternative to likelihood_ratios: provide P(E|H) and P(E|¬H) for each piece of evidence."
        }
      },
      required: ['prior']
    }
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

    def calculate(arguments)
      expression = arguments['expression']
      result = Calculator.evaluate(expression)
      result.to_s
    end

    def bayesian_update(arguments)
      prior = Float(arguments['prior'])
      raise ArgumentError, 'prior must be between 0 and 1' unless (0..1).cover?(prior)

      # Collect likelihood ratios from both input modes
      lrs = Array(arguments['likelihood_ratios']).map { |v| Float(v) }
      Array(arguments['evidence_items']).each do |item|
        p_e_h = Float(item['p_e_given_h'])
        p_e_not_h = Float(item['p_e_given_not_h'])
        raise ArgumentError, 'P(E|¬H) must be > 0' if p_e_not_h.zero?

        lrs << p_e_h / p_e_not_h
      end

      raise ArgumentError, 'at least one likelihood ratio or evidence item required' if lrs.empty?

      # Clamp edge cases to avoid NaN/Infinity.
      # Use 1e-9 so extreme posteriors are still distinguishable after
      # floating-point normalization (avoiding exact 0.0 / 1.0).
      prior_clamped = prior.clamp(1e-9, 1.0 - 1e-9)
      combined_lr = lrs.reduce(1.0, :*)

      posterior = (prior_clamped * combined_lr) /
                  (prior_clamped * combined_lr + (1.0 - prior_clamped))

      # Return posterior + diagnostic metadata
      {
        posterior: posterior,
        prior: prior,
        combined_likelihood_ratio: combined_lr.round(4),
        evidence_count: lrs.length,
        shift_magnitude: (posterior - prior).abs,
        direction: posterior > prior ? 'supporting' : posterior < prior ? 'opposing' : 'neutral'
      }
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
      when 'calculate'
        calculate(arguments)
      when 'bayesian_update'
        bayesian_update(arguments).to_json
      else
        raise "Unknown Tool Requested: `#{tool}`"
      end
    end
  end
end
