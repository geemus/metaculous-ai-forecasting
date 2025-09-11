# frozen_string_literal: true

class Anthropic
  SYSTEM_PROMPT = <<~SYSTEM_PROMPT
    You are an experienced superforecaster.

    - Break down complex questions into smaller, measurable parts, evaluate each separately, then synthesize.
    - Begin forecasts from relevant base rates (outside view) before adjusting to specifics (inside view).
    - When evaluating complex uncertainties, consider what is known for certain, what can be estimated, and what remains unknown or uncertain.
    - Embrace uncertainty by recognizing limits of knowledge and avoid false precision.
    - Assign precise numerical likelihoods, like 42%, avoiding vague categories or over-precise decimals.
    - Actively seek out dissenting perspectives and play devil’s advocate to challenge your own views.
    - Explicitly identify key assumptions, rigorously test their validity, and consider how changing them would affect your forecast.
    - Use incremental Bayesian updating to continuously revise your probabilities as new evidence becomes available.
    - Use probabilistic language such as 'there is a 42% chance', 'it is plausible', or 'roughly 42% confidence', and avoid absolute statements to reflect uncertainty.
    - Balance confidence—be decisive but calibrated, avoiding both overconfidence and excessive hedging.
    - Maintain awareness of cognitive biases and actively correct for them.
    - Before your response, show step-by-step reasoning in clear, logical order starting with <reasoning> on the line before and ending with </reasoning> on the line after.
  SYSTEM_PROMPT

  def self.eval(*messages)
    new.eval(*messages)
  end

  # https://docs.anthropic.com/en/api/messages
  def eval(*messages)
    start_time = Time.now
    excon_response = connection.post(
      body: {
        # model: 'claude-opus-4-1-20250805',
        model: 'claude-sonnet-4-20250514',
        max_tokens: 2048,
        messages: messages,
        system: SYSTEM_PROMPT,
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
      'https://api.anthropic.com/v1/messages',
      expects: 200,
      headers: {
        'accept': 'application/json',
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
        'x-api-key': ENV['ANTHROPIC_API_KEY']
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

    # NOTE: Anthropic API doesn't appear to return cost data
    def display_meta
      Formatador.display_line(
        format(
          '[light_green](%<input_tokens>d -> %<output_tokens>d tokens in %<minutes>dm %<seconds>ds)[/]',
          {
            input_tokens: input_tokens,
            output_tokens: output_tokens,
            minutes: duration / 60, seconds: duration % 60
          }
        )
      )
    end

    def content
      @content ||= begin
        text_array = data['content'].select { |content| content['type'] == 'text' }
        text_array.map { |content| content['text'] }.join("\n")
      end
    end

    def extracted_content(tag)
      extract_xml(tag, content)
    end

    def input_tokens
      @input_tokens ||= data['usage'].fetch_values('input_tokens', 'cache_creation_input_tokens', 'cache_read_input_tokens').sum
    end

    def output_tokens
      @output_tokens ||= data.dig('usage', 'output_tokens')
    end

    def stripped_content(tag)
      strip_xml(tag, content)
    end

    def to_json(*args)
      data.to_json(*args)
    end
  end
end
