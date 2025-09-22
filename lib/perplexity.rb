# frozen_string_literal: true

class Perplexity
  attr_accessor :model, :system, :temperature

  def initialize(
    model: 'sonar-reasoning',
    system: RESEARCHER_SYSTEM_PROMPT,
    temperature: 0.1
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
        # max_tokens: 2048,
        model: model,
        messages: [
          {
            'role': 'system',
            'content': system
          }
        ].concat(messages),
        temperature: temperature,
        web_search_options: {
          search_context_size: 'low'
        }
      }.to_json
    )
    response = Response.new(
      duration: Time.now - start_time,
      data: JSON.parse(excon_response.body)
    )
    response.display_meta
    response
  rescue Excon::Error => e
    puts e
    exit(1)
  end

  private

  def connection
    Excon.new(
      'https://api.perplexity.ai/chat/completions',
      expects: 200,
      headers: {
        'accept': 'application/json',
        'authorization': "Bearer #{ENV['PERPLEXITY_API_KEY']}",
        'content-type': 'application/json'
      },
      read_timeout: 600
    )
  end

  class Response
    attr_accessor :data, :duration

    def initialize(data:, duration: nil)
      @data = data
      @duration = duration
    end

    def display_meta
      Formatador.display_line(
        format(
          '[light_green](%<total>d: %<input>d -> %<output>d tokens in %<minutes>dm %<seconds>ds @ $%<cost>0.2f)[/]',
          {
            total: total_tokens,
            input: input_tokens,
            output: output_tokens,
            minutes: @duration / 60,
            seconds: @duration % 60,
            cost: cost
          }
        )
      )
    end

    def content
      @content ||= data['choices'].map { |choice| choice['message']['content'] }.join("\n")
    end

    def cost
      @data.dig('usage', 'cost', 'total_cost')
    end

    def extracted_content(tag)
      extract_xml(tag, content)
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
      @output_tokens ||= data.dig('usage', 'total_tokens') - data.dig('usage', 'prompt_tokens')
    end

    def percentiles
      @percentiles ||= begin
        percentiles = {}
        extracted_content('percentiles').split("\n").each do |line|
          key, value = line.split(': ', 2)
          key = key.split('Percentile ', 2).last
          value = value.split(' ', 2).first
          percentiles[key.to_i] = value.include?('.') ? value.to_f : value.to_i
        end
        percentiles
      end
    end

    def probabilities
      @probabilities ||= begin
        probabilities = {}
        extracted_content('probabilities').split("\n").each do |line|
          pair = line.split('Option "', 2).last
          key, value = pair.split('": ', 2)
          probabilities[key] = value.include?('%') ? value.to_f / 100.0 : value.to_f
        end
        probabilities
      end
    end

    def probability
      @probability ||= begin
        probability = extracted_content('probability')
        probability.include?('%') ? probability.to_f / 100.0 : probability.to_f
      end
    end

    def stripped_content(tag)
      strip_xml(tag, content)
    end

    def to_json(*args)
      data.to_json(*args)
    end

    def total_tokens
      @total_tokens ||= data.dig('usage', 'total_tokens')
    end
  end
end
