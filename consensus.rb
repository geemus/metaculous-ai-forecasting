#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/script_helpers'

FORECASTERS = Provider::FORECASTERS

post_id = ARGV[0] || raise('post id argument is required')

question = fetch_question(post_id)
exit if should_skip_forecast?(question, post_id)

@research_output = load_research(post_id, strip_tags: 'reflect')
@revised_forecasts = load_forecasts(post_id, type: 'revision')

retries_remaining = 3

begin
  provider = :deepseek
  Formatador.display "\n[bold][green]# Superforecaster: Summarizing Consensus(#{post_id})…[/] "
  consensus_json = cache(post_id, 'forecasts/consensus.json') do
    llm = Provider.new(provider)
    consensus_prompt = prompt_with_type(llm, question, FORECAST_CONSENSUS_PROMPT_TEMPLATE)
    cache_write(post_id, 'inputs/consensus.md', consensus_prompt)
    consensus = llm.eval({ 'role': 'user', 'content': consensus_prompt })
    cache_write(post_id, 'outputs/consensus.md', consensus.content)
    cache_concat(post_id, 'reflects.md', "# Consensus\n#{consensus.extracted_content('reflect')}")
    consensus.to_json
  end
  consensus = Response.new(provider, json: consensus_json)
  puts consensus.content

  question.submit(consensus)
rescue StandardError => e
  puts e.message
  puts "! Retries remaining: #{retries_remaining - 1}"
  cache_delete(post_id, 'forecasts/consensus.json')
  retry if (retries_remaining -= 1).positive?
end
