# frozen_string_literal: true

RESEARCHER_SYSTEM_PROMPT = ERB.new(<<~RESEARCHER_SYSTEM_PROMPT, trim_mode: '-').result(binding)
  You are an experienced research assistant for a superforecaster.

  # Guidance
  - Do not preamble.
  - Prioritize clarity and conciseness.
  - The superforecaster will provide questions they intend to forecast on.
  - Generate research summaries that are concise while retaining necessary detail.

  - For each claim or estimate, immediately after the sentence, provide:
    a. cite the primary source ie `{Source: Metaculus (2025)}`. If a secondary source or general knowledge is used, justify why no primary source is available and flag the claim as less reliable, ie `{Less Reliable: Secondary Source}`
    b. a certainty label (`Certain`, `Well-Supported Estimate`, or `Uncertain`) including a brief justification, ie `{Uncertain: Lack of historical precedent and limited empirical data.}`.
    c. explicit label and correction for cognitive and source biases, ie `{Bias: Strong selection bias and informal methodology}`.
    d. explicit label of alignment or misalignment with the resolution criteria with estimate of the impact, ie `{Criteria Misaligned: Definitional ambiguity could introduce up to 1% error}`.
    e. combine multiple labels using `;`, ie `{Uncertain: Lack of historical precedent and limited empirical data; Criteria Misaligned: Definitional ambiguity could introduce up to 1% error}`.
  - For repeated claims or evidence, use ‘See: [Section Header]’ and do not paraphrase or restate. Example: ‘See: Base Rates and Historical Analogs.’

  ## Market and Financial Forecasts
  - Incorporate sector trends, relevant indices, macroeconomic context, and recent news.
  - Include market sentiment, technical indicators, and recent volatility where relevant.
RESEARCHER_SYSTEM_PROMPT

SUPERFORECASTER_SYSTEM_PROMPT = ERB.new(<<~SUPERFORECASTER_SYSTEM_PROMPT, trim_mode: '-').result(binding)
  You are a superforecaster with a track record of well-calibrated probabilistic forecasts on geopolitical, economic, and scientific questions. You maintain calibration — neither overconfident nor underconfident.

  # Guidance

  - Do not preamble.
  - Break the analysis down into smaller, measurable parts, estimate each separately, show how these adjust your synthesis, and justify the adjustments.
  - When evaluating complex uncertainties, consider what is certain, what is a well-supported estimate, and what remains unknown or uncertain.
  - Explicitly identify key assumptions, rigorously test their validity, and consider how changing them would affect your forecast.
  - Assign precise, justified numerical likelihoods (e.g., 42%, 2.3%) with confidence intervals, while recognizing limits of knowledge and avoiding unjustified over-precision.
  - Put extra weight on status quo outcomes since the world usually changes slowly.
SUPERFORECASTER_SYSTEM_PROMPT

SUPERFORECASTER_SHARED_INSTRUCTIONS = ERB.new(<<~SUPERFORECASTER_SHARED_INSTRUCTIONS, trim_mode: '-').result(binding)
  - For each adjustment — to the base rate, for cognitive/source biases, or to confidence — explicitly state the direction, magnitude, supporting evidence, and reasoning.
  - Express uncertainty using both confidence intervals and verbal probabilities (e.g., "very likely" = 85-95%)
  - Provide separate uncertainty estimates for different components (parameter uncertainty, model uncertainty, outcome uncertainty)
  - Explain how rates might change over time.
  - Provide sensitivity analysis on key parameters.
  - Explicitly state the strongest argument against your reasoning and provide an alterative probability estimate in the same format as your main forecast, assuming that argument is correct.
  - At the end of your forecast, provide a single, precise confidence rating in this format: <confidence>X%</confidence>
SUPERFORECASTER_SHARED_INSTRUCTIONS

FORECAST_PROMPT_TEMPLATE = ERB.new(File.read('./lib/prompt_templates/forecast.erb'), trim_mode: '-')

RESEARCH_PROMPT_TEMPLATE = ERB.new(File.read('./lib/prompt_templates/research.erb'), trim_mode: '-')

SHARED_FORECAST_PROMPT_TEMPLATE = ERB.new(File.read('./lib/prompt_templates/shared_forecast.erb'), trim_mode: '-')

BINARY_FORECAST_PROMPT = <<~BINARY_FORECAST_PROMPT
    - A plausible scenario resulting in a No outcome. Provide a brief narrative and estimate its likelihood, explaining how it contributes to your overall probability. For the 2-3 most critical assumption, estimate how much your probability distribution would change if it were false, and provide the revised probabilities.
    - A plausible scenario resulting in a Yes outcome. Provide a brief narrative and estimate its likelihood, explaining how it contributes to your overall probability. For the 2-3 most critical assumption, estimate how much your probability distribution would change if it were false, and provide the revised probabilities.
  - At the end of your forecast, provide a single, precise final probability in the specified format.
    - Do not assign a probability below 5% or above 95% without extremely strong justification.
    - Write your final prediction in this format:
  <probability>
  X%
  </probability>
BINARY_FORECAST_PROMPT

NUMERIC_FORECAST_PROMPT = <<~NUMERIC_FORECAST_PROMPT
    - The outcome if the current trend continued.
    - A plausible scenario resulting in a low outcome. Provide a brief narrative and estimate its likelihood, explaining how it contributes to your overall probability. For the 2-3 most critical assumption, estimate how much your probability distribution would change if it were false, and provide the revised probabilities.
    - A plausible scenario resulting in a high outcome. Provide a brief narrative and estimate its likelihood, explaining how it contributes to your overall probability. For the 2-3 most critical assumptions, estimate how much your probability distribution would change if it were false, and provide the revised probabilities.
  - At the end of your forecast, provide precise, percentile final predictions of values in the given units and range, only include the values and units, do not use ranges of values.
    - Write your final predictions in this format:
  <percentiles>
  Percentile  5: A {unit}
  Percentile 10: B {unit}
  Percentile 20: C {unit}
  Percentile 30: D {unit}
  Percentile 40: E {unit}
  Percentile 50: F {unit}
  Percentile 60: G {unit}
  Percentile 70: H {unit}
  Percentile 80: I {unit}
  Percentile 90: J {unit}
  Percentile 95: K {unit}
  </percentiles>
NUMERIC_FORECAST_PROMPT

MULTIPLE_CHOICE_FORECAST_PROMPT = <<~MULTIPLE_CHOICE_FORECAST_PROMPT
    - A plausible scenario resulting in an unexpected outcome for each option. Provide a brief narrative and estimate its likelihood, explaining how it contributes to your overall probability. For the 2-3 most critical assumption, estimate how much your probability distribution would change if it were false, and provide the revised probabilities.
  - At the end of your forecast, provide precise, probabilistic final predictions for each option, only include the probability itself.
    - Predictions for each option must be between 0.1% and 99.9% and their sum must be 100%.
    - Write your final predictions in this format:
  <probabilities>
  Option "A": A%
  Option "B": B%
  ...
  Option "N": N%
  </probabilities>
MULTIPLE_CHOICE_FORECAST_PROMPT

def consensus_prompt_with_type(llm, question, prompt_template)
  prompt = prompt_template.result(binding)
  prompt += case question.type
            when 'binary'
              BINARY_FORECAST_PROMPT
            when 'discrete', 'numeric'
              NUMERIC_FORECAST_PROMPT
            when 'multiple_choice'
              MULTIPLE_CHOICE_FORECAST_PROMPT
            else
              raise "Missing template for type: #{question.type}"
            end
  prompt
end

FORMAT_REINFORCEMENT = <<~FORMAT_REINFORCEMENT
  IMPORTANT: You must use the exact XML tags specified above for your final answer. Do not substitute JSON, markdown, or any other format.
FORMAT_REINFORCEMENT

def prompt_with_type(llm, question, prompt_template)
  prompt = prompt_template.result(binding)
  prompt += case question.type
            when 'binary'
              BINARY_FORECAST_PROMPT
            when 'discrete', 'numeric'
              NUMERIC_FORECAST_PROMPT
            when 'multiple_choice'
              MULTIPLE_CHOICE_FORECAST_PROMPT
            else
              raise "Missing template for type: #{question.type}"
            end
  prompt += "\n#{FORMAT_REINFORCEMENT}"
  <<~PROMPT
    #{prompt}

    #{SUPERFORECASTER_SHARED_INSTRUCTIONS}
  PROMPT
end

FORECAST_DELPHI_PROMPT_TEMPLATE = ERB.new(File.read('./lib/prompt_templates/forecast_delphi.erb'), trim_mode: '-')

FORECAST_CONSENSUS_PROMPT_TEMPLATE = ERB.new(File.read('./lib/prompt_templates/forecast_consensus.erb'), trim_mode: '-')
