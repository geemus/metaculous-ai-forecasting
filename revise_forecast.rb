#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/script_helpers'

FORECASTERS = Provider::FORECASTERS

post_id = ARGV[0] || raise('post id argument is required')
forecaster_index = ARGV[1]&.to_i || raise('forecaster index argv[1] is required')

question = fetch_question(post_id)
exit if should_skip_forecast?(question, post_id)

@research_output = load_research(post_id, strip_tags: 'reflect')
@forecasts = load_forecasts(post_id, type: 'forecast')

provider = FORECASTERS[forecaster_index]
@forecast = @forecasts[forecaster_index]

Formatador.display "\n[bold][green]# Superforecaster[#{forecaster_index}: #{provider}]: Revising Forecast(#{post_id})…[/] "
cache(post_id, "forecasts/revision.#{forecaster_index}.json") do
  llm_args = { system: SUPERFORECASTER_SYSTEM_PROMPT, temperature: 0.1 }
  llm = Provider.new(provider, **llm_args)
  forecast_prompt = prompt_with_type(llm, question, SHARED_FORECAST_PROMPT_TEMPLATE)
  forecast_delphi_prompt = FORECAST_DELPHI_PROMPT_TEMPLATE.result(binding)
  cache_write(post_id, "inputs/revision.#{forecaster_index}.md", forecast_delphi_prompt)
  revision = llm.eval(
    { 'role': 'user', 'content': forecast_prompt },
    { 'role': 'assistant', 'content': @forecast.content },
    { 'role': 'user', 'content': forecast_delphi_prompt }
  )
  puts revision.content
  cache_write(post_id, "outputs/revision.#{forecaster_index}.md", revision.content)
  cache_concat(post_id, 'reflects.md',
               "# Revision {#{forecaster_index}: #{provider}}\n#{revision.extracted_content('reflect')}\n\n")
  revision.to_json
end
