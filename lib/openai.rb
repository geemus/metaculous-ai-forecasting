# frozen_string_literal: true

require './lib/helpers/response'

class OpenAI
  attr_accessor :model, :system, :temperature

  def initialize(
    model: 'gpt-5-nano',
    system: SUPERFORECASTER_SYSTEM_PROMPT,
    temperature: 1.0 # only supported value with gpt-5-mini
  )
    @model = model
    @system = system
    @temperature = temperature
  end

  # https://docs.perplexity.ai/api-reference/chat-completions-post
  def eval(*messages)
    start_time = Time.now
    excon_response = connection.post(
      body: {
        # max_completion_tokens: 2048,
        model: model,
        messages: [
          {
            'role': 'system',
            'content': system
          }
        ].concat(messages),
        temperature: temperature
      }.to_json
    )
    response = Response.new(
      duration: Time.now - start_time,
      json: excon_response.body
    )
    response.display_meta
    response
  rescue Excon::Error => e
    puts e
    puts e.response.body
    exit(1)
  end

  private

  def connection
    Excon.new(
      'https://api.openai.com/v1/chat/completions',
      expects: 200,
      headers: {
        'accept': 'application/json',
        'authorization': "Bearer #{ENV['OPENAI_API_KEY']}",
        'content-type': 'application/json'
      },
      read_timeout: 600
    )
  end

  class Response
    include ResponseHelpers

    attr_accessor :data, :duration

    def initialize(duration: nil, json: '{}')
      @data = JSON.parse(json)
      @duration = duration
    end

    def display_meta
      Formatador.display_line(
        format(
          '[light_green](%<total>d: %<input>d -> %<output>d tokens in %<minutes>dm %<seconds>ds)[/]',
          {
            total: total_tokens,
            input: input_tokens,
            output: output_tokens,
            minutes: @duration / 60,
            seconds: @duration % 60
          }
        )
      )
    end

    def content
      @content ||= data['choices'].map { |choice| choice['message']['content'] }.join("\n")
    end

    def formatted_research
      ERB.new(<<~RESEARCH_OUTPUT, trim_mode: '-').result(binding)
        <%= stripped_content('think') %>

        <sources>
        <% data['search_results'].each do |result| -%>
        - [<%= result['title'] %>](<%= result['url'] %>) <%= result['snippet'] %> (Published: <%= result['date'] %>, Updated: <%= result['last_updated'] %>)
        <% end -%>
        </sources>
      RESEARCH_OUTPUT
    end

    def input_tokens
      @input_tokens ||= data.dig('usage', 'prompt_tokens')
    end

    def output_tokens
      @output_tokens ||= data.dig('usage', 'completion_tokens')
    end

    def total_tokens
      @total_tokens ||= data.dig('usage', 'total_tokens')
    end
  end
end
