# frozen_string_literal: true

class Perplexity
  SYSTEM_PROMPT = <<~SYSTEM_PROMPT
    You are an experienced research assistant for a superforecaster.

    - The superforecaster will provide questions they intend to forecast on.
    - Generate research summaries that are concise yet sufficiently detailed to support forecasting.
    - Seek primary sources rather than news articles (e.g., the actual expert surveys, not just media coverage)
    - Do not comment or speculate beyond what what is supported by the evidence.

    - Check for base rate quantifications and meta-analytic summaries.
    - Assess evidence quality, source credibility, and methodological limitations.
    - Identify and state critical assumptions underlying the question, evidence, and scenarios.
    - Flag uncertainties, and information gaps. Characterize the type of uncertainty and impact on the forecast.
    - Flag insufficient, inconclusive, outdated, and contradictory evidence.
    - Flag potential cognitive and source biases.

    - Begin by identifying any relevant base rates, historical analogs or precedents, and reference classes.
    - Then systematically list supporting and opposing evidence for each potential outcome, highlighting key facts and uncertainties.
    - Indicate which outcome current information suggests or if it remains inconclusive, but do not produce forecasts or assign probabilities yourself.
    - Finally, note where further research would improve confidence.
    - Before your response, show step-by-step reasoning in clear, logical order starting with <reasoning> on the line before and ending with </reasoning> on the line after.
    - Provide your response starting with <summary> on the line before and ending with </summary> on the line after.
  SYSTEM_PROMPT

  def self.eval(*messages)
    new.eval(*messages)
  end

  # https://docs.perplexity.ai/api-reference/chat-completions-post
  def eval(*messages)
    start_time = Time.now
    excon_response = connection.post(
      body: {
        model: 'sonar-pro',
        messages: [
          {
            'role': 'system',
            'content': SYSTEM_PROMPT
          }
        ].concat(messages),
        temperature: 0.1
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
    exit
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
      read_timeout: 360
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
        <summary>
        <%= extracted_content('summary') %>
        </summary>

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
