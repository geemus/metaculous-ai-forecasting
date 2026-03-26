#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/script_helpers'

FORECASTERS = Provider::FORECASTERS

post_id = ARGV[0] || raise('post id argv[0] is required')
forecaster_index = ARGV[1]&.to_i || raise('forecaster index argv[1] is required')

question = fetch_question(post_id)
exit if should_skip_forecast?(question, post_id)

@research_output = load_research(post_id, strip_tags: 'reflect')

provider = FORECASTERS[forecaster_index]
Formatador.display "\n[bold][green]# Superforecaster[#{forecaster_index}: #{provider}]: Forecasting(#{post_id})…[/] "
cache(post_id, "forecasts/forecast.#{forecaster_index}.json") do
  system_prompt = system_prompt_for(provider)
  cache_write(post_id, "inputs/system.#{forecaster_index}.md", system_prompt)
  llm_args = { system: system_prompt, temperature: 0.9 }
  llm = Provider.new(provider, **llm_args)
  forecast_prompt = prompt_with_type(llm, question, SHARED_FORECAST_PROMPT_TEMPLATE)
  cache_write(post_id, "inputs/forecast.#{forecaster_index}.md", forecast_prompt)
  forecast = llm.eval({ 'role': 'user', 'content': forecast_prompt })
  puts forecast.content
  cache_write(post_id, "outputs/forecast.#{forecaster_index}.md", forecast.content)
  cache_concat(post_id, 'reflects.md',
               "# Forecast {#{forecaster_index}: #{provider}}\n#{forecast.extracted_content('reflect')}\n\n")
  forecast.to_json
end
