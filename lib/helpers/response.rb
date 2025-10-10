# frozen_string_literal: true

module ResponseHelpers
  def extracted_content(*tags)
    extract_xml(content, *tags).last
  end

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
      probability = [probability, 0.001].max # probability_yes must be >= 0.001
      probability = [probability, 0.999].min # probability_yes must be <= 0.999
      probability
    end
  end

  def stripped_content(*tags)
    strip_xml(content, *tags)
  end

  def to_json(*args)
    data.to_json(*args)
  end
end
