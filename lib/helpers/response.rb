# frozen_string_literal: true

module ResponseHelpers
  def extracted_content(*tags)
    extract_xml(content, *tags).last
  end

  EXPECTED_PERCENTILE_KEYS = [5, 10, 20, 25, 30, 40, 50, 60, 70, 75, 80, 90, 95].freeze

  def percentiles
    @percentiles ||= begin
      percentiles = {}
      extracted_content('percentiles').split("\n").each do |line|
        key, value = line.split(': ', 2)
        key = key.split('Percentile ', 2).last
        value = value.split(' ', 2).first
        value.gsub!(',', '')
        percentiles[key.to_i] = value.to_f
      end

      missing = EXPECTED_PERCENTILE_KEYS - percentiles.keys
      warn "WARNING: missing percentiles #{missing}" unless missing.empty?

      sorted_values = percentiles.sort_by { |k, _| k }.map { |_, v| v }
      unless sorted_values == sorted_values.sort
        warn "WARNING: percentile values are not monotonically increasing: #{percentiles.inspect}"
      end

      percentiles
    end
  end

  def probabilities
    @probabilities ||= begin
      probabilities = {}
      extracted_content('probabilities').split("\n").each do |line|
        line = line.gsub('Option ', '')
        line = line.gsub('"', '')
        key, value = line.split(': ', 2)
        probabilities[key] = value.include?('%') ? value.to_f / 100.0 : value.to_f
      end
      probabilities
    end
  end

  def probability
    @probability ||= begin
      probability = extracted_content('probability')
      probability = probability.include?('%') ? probability.to_f / 100.0 : probability.to_f
      clamped = probability.clamp(0.001, 0.999)
      warn "WARNING: probability #{probability} clamped to #{clamped}" if clamped != probability
      clamped
    end
  end

  def stripped_content(*tags)
    strip_xml(content, *tags)
  end

  def model
    data['model']
  end

  def to_json(*args)
    data.to_json(*args)
  end
end
