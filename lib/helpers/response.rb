# frozen_string_literal: true

module ResponseHelpers
  def extracted_content(*tags)
    extract_xml(content, *tags)
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

  def stripped_content(*tags)
    strip_xml(content, *tags)
  end

  def to_json(*args)
    data.to_json(*args)
  end
end
