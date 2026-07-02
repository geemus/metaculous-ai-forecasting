# frozen_string_literal: true

require_relative 'aggregation'

# Assembles a structured pipeline comment from cached run data.
#
# Usage:
#   rich_comment = CommentBuilder.build_pipeline_comment(
#     post_id, question, consensus_response, revised_forecasts
#   )
#
# Returns a markdown string suitable for posting as a private Metaculus comment.
module CommentBuilder
  MAX_COMMENT_LENGTH = 10_000
  SECTION_SEPARATOR = "\n\n---\n\n"

  def self.build_pipeline_comment(post_id, question, consensus_response, revised_forecasts)
    sections = []

    sections << build_pipeline_overview(post_id, question)
    sections << build_research_highlights(post_id)
    sections << build_news_context(post_id)
    sections << build_forecaster_positions(question, revised_forecasts)
    sections << build_consensus_analysis(consensus_response)
    sections << build_final_forecast(consensus_response, question)

    # Join non-nil sections and enforce max length
    comment = sections.compact.join(SECTION_SEPARATOR)
    enforce_max_length(comment)
  end

  # ---------------------------------------------------------------------------
  # Section builders
  # ---------------------------------------------------------------------------

  def self.build_pipeline_overview(post_id, question)
    stages = "News → Research → 4 Forecasters → Delphi Revise → Consensus"

    lines = []
    lines << "## Pipeline Overview"
    lines << "- **Question:** #{question.title}"
    lines << "- **Type:** #{question.type}"
    lines << "- **Post ID:** #{post_id}"
    lines << "- **Stages:** #{stages}"

    # News article count + date range
    news_data = load_news(post_id)
    if news_data
      articles = news_data['as_dicts'] || []
      count = articles.size
      lines << "- **News articles:** #{count}"

      dates = articles.map { |a| a['pub_date'] }.compact.sort
      unless dates.empty?
        first_date = dates.first[0..9]
        last_date  = dates.last[0..9]
        date_range = first_date == last_date ? first_date : "#{first_date} → #{last_date}"
        lines << "- **News date range:** #{date_range}"
      end
    end

    # Mechanical baseline
    baseline = mechanical_baseline_from_cache(post_id, question)
    lines << "- **Mechanical baseline:** #{baseline}" if baseline

    lines.join("\n")
  rescue StandardError => e
    warn "CommentBuilder: pipeline overview failed: #{e.message}"
    nil
  end

  def self.build_research_highlights(post_id)
    research = load_research_response(post_id)
    return nil unless research

    content = research.content.to_s.strip
    return nil if content.empty?

    lines = []
    lines << "## Research Highlights"

    sections = parse_research_sections(content)
    sections.each do |header, body|
      next if body.strip.empty?

      bullets = extract_key_points(body, max: 2)
      lines << "### #{header}"
      bullets.each { |b| lines << "- #{b}" }
    end

    lines.size > 1 ? lines.join("\n") : nil
  rescue StandardError => e
    warn "CommentBuilder: research highlights failed: #{e.message}"
    nil
  end

  def self.build_news_context(post_id)
    news_data = load_news(post_id)
    return nil unless news_data

    articles = news_data['as_dicts'] || []
    return nil if articles.empty?

    lines = []
    lines << "## News Context"
    lines << "- **Articles:** #{articles.size}"
    lines << "- **Sources:** #{articles.map { |a| a['source_id'] }.uniq.sort.join(', ')}"

    # Top 5 article titles with one-line summary
    titles = articles.first(5).map do |article|
      title   = article['eng_title'] || 'Untitled'
      summary = article['summary'] || ''
      # Take first sentence of summary (up to 160 chars)
      one_liner = truncate_sentence(summary, 160)
      "- **#{title}** — #{one_liner}"
    end

    lines.concat(titles)
    lines.join("\n")
  rescue StandardError => e
    warn "CommentBuilder: news context failed: #{e.message}"
    nil
  end

  def self.build_forecaster_positions(question, revised_forecasts)
    return nil if revised_forecasts.nil? || revised_forecasts.empty?

    lines = []
    lines << "## Forecaster Positions"
    lines << ""
    lines << "| Provider | #{forecast_column_header(question)} | Confidence | Key Argument |"
    lines << "|----------|#{'-' * [forecast_column_header(question).length, 10].max}|------------|--------------|"

    revised_forecasts.each_with_index do |forecast, idx|
      provider   = forecast.provider.to_s
      forecast_val = format_forecast_value(question, forecast)
      confidence = format_confidence(forecast)
      key_arg    = extract_key_argument(forecast)

      lines << "| #{provider} | #{forecast_val} | #{confidence} | #{key_arg} |"
    rescue StandardError => e
      warn "CommentBuilder: forecaster #{idx} failed: #{e.message}"
      lines << "| #{forecast.provider} | — | — | *(parse error)* |"
    end

    lines.join("\n")
  rescue StandardError => e
    warn "CommentBuilder: forecaster positions failed: #{e.message}"
    nil
  end

  def self.build_consensus_analysis(consensus_response)
    return nil unless consensus_response

    synthesis = consensus_response.stripped_content('think').to_s.strip
    return nil if synthesis.empty?

    ["## Consensus Analysis", synthesis].join("\n")
  rescue StandardError => e
    warn "CommentBuilder: consensus analysis failed: #{e.message}"
    nil
  end

  def self.build_final_forecast(consensus_response, question)
    return nil unless consensus_response && question

    case question.type
    when 'binary'
      prob = consensus_response.probability
      ["## Final Forecast", "", "<probability>", "#{(prob * 100).round(1)}%", "</probability>"].join("\n")
    when 'numeric', 'discrete'
      pcts = consensus_response.percentiles
      return nil if pcts.nil? || pcts.empty?

      lines = ["## Final Forecast", "", "<percentiles>"]
      pcts.sort.each do |key, value|
        lines << "Percentile #{key.to_s.rjust(2)}: #{value.round(3)} #{question.units}"
      end
      lines << "</percentiles>"
      lines.join("\n")
    when 'multiple_choice'
      probs = consensus_response.probabilities
      return nil if probs.nil? || probs.empty?

      lines = ["## Final Forecast", "", "<probabilities>"]
      probs.each do |key, value|
        lines << "#{key}: #{(value * 100).round(1)}%"
      end
      lines << "</probabilities>"
      lines.join("\n")
    else
      nil
    end
  rescue StandardError => e
    warn "CommentBuilder: final forecast failed: #{e.message}"
    nil
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  def self.load_news(post_id)
    path = cache_path(post_id, 'news.json')
    return nil unless File.exist?(path)

    JSON.parse(File.read(path))
  rescue StandardError
    nil
  end

  def self.load_research_response(post_id)
    path = cache_path(post_id, 'research.json')
    return nil unless File.exist?(path)

    Response.new(:open_router, json: File.read(path))
  rescue StandardError
    nil
  end

  def self.parse_research_sections(content)
    # Split on ### headers (1-4) and map header name to body text
    sections = {}
    current_header = nil
    current_body = []

    content.each_line do |line|
      if line =~ /^###\s+([\d]+\.\s+.+)$/
        # Save previous section
        if current_header
          sections[current_header] = current_body.join.strip
        end
        current_header = $1.strip
        current_body = []
      elsif current_header
        current_body << line
      end
    end

    # Don't miss the last section
    if current_header
      sections[current_header] = current_body.join.strip
    end

    sections
  end

  def self.extract_key_points(body, max: 2)
    # Split body into sentences and take the first `max` substantive ones
    sentences = body.split(/(?<=[.!?])\s+/).map(&:strip).reject(&:empty?)
    sentences = sentences.reject { |s| s =~ /^\{/ }          # skip metadata braces
    sentences = sentences.reject { |s| s =~ /^#/ }           # skip markdown headers
    sentences = sentences.reject { |s| s.length < 10 }       # skip very short fragments
    # Strip leading "- " or "* " bullets from sentences so we don't double-bullet
    sentences = sentences.map { |s| s.sub(/^[-*]\s+/, '') }
    sentences.first(max)
  end

  def self.truncate_sentence(text, max_chars)
    return text if text.length <= max_chars

    truncated = text[0...max_chars]
    # Cut at last word boundary
    last_space = truncated.rindex(' ')
    truncated = truncated[0...last_space] if last_space
    "#{truncated}…"
  end

  def self.forecast_column_header(question)
    case question.type
    when 'binary' then 'Probability'
    when 'numeric', 'discrete' then 'P50'
    when 'multiple_choice' then 'Top Option'
    else 'Forecast'
    end
  end

  def self.format_forecast_value(question, forecast)
    case question.type
    when 'binary'
      prob = forecast.probability
      "#{(prob * 100).round(1)}%"
    when 'numeric', 'discrete'
      pcts = forecast.percentiles
      p50 = pcts[50] || pcts['50'] || '—'
      unit_str = question.units.to_s.empty? ? '' : " #{question.units}"
      "#{p50}#{unit_str}"
    when 'multiple_choice'
      probs = forecast.probabilities
      return '—' if probs.nil? || probs.empty?

      top = probs.max_by { |_, v| v }
      "#{top[0]}: #{(top[1] * 100).round(1)}%"
    else
      '—'
    end
  rescue StandardError
    '—'
  end

  def self.format_confidence(forecast)
    confidence = forecast.extracted_content('confidence')
    return '—' if confidence.nil? || confidence.to_s.strip.empty?

    confidence.to_s.strip
  rescue StandardError
    '—'
  end

  def self.extract_key_argument(forecast)
    stripped = forecast.stripped_content('think').to_s.strip
    return '—' if stripped.empty?

    # Split into paragraph chunks, then individual lines, then sentences
    paragraphs = stripped.split(/\n\n+/).map(&:strip).reject(&:empty?)
    candidates = paragraphs.flat_map { |p| p.split(/\n/) }.map(&:strip).reject(&:empty?)
    # Further split long lines on sentence boundaries
    candidates = candidates.flat_map { |l| l.split(/(?<=[.!?])\s+/) }.map(&:strip).reject(&:empty?)

    key_sentence = candidates.find do |s|
      s.length > 20 &&
        s !~ /^\s*\{/ &&          # skip metadata braces
        s !~ /^\s*#/ &&           # skip markdown headers
        s !~ /^\s*\*{1,2}[^*]+\*{1,2}:?\s*$/  # skip bold/italic label-only lines
    end
    key_sentence ? truncate_sentence(key_sentence, 200) : truncate_sentence(stripped, 200)
  rescue StandardError
    '—'
  end

  def self.cache_path(post_id, path)
    "./tmp/#{post_id}/#{path}"
  end

  def self.mechanical_baseline_from_cache(post_id, question)
    # Build mechanical baseline from cached revision forecasts
    forecasts = load_revision_forecasts(post_id)
    return nil if forecasts.nil? || forecasts.empty?

    case question.type
    when 'binary'
      pooled = Aggregation.pool_binary(forecasts.map(&:probability))
      a = Aggregation.extremization_factor
      if a == 1.0
        "Log-odds mean: #{(pooled * 100).round(1)}%"
      else
        "Log-odds pool (extremization a=#{a}): #{(pooled * 100).round(1)}%"
      end
    when 'multiple_choice'
      pooled = Aggregation.pool_multiple_choice(forecasts.map(&:probabilities))
      lines = pooled.map { |k, v| "  #{k}: #{(v * 100).round(1)}%" }
      a = Aggregation.extremization_factor
      if a == 1.0
        "Softmax-of-log mean:\n#{lines.join("\n")}"
      else
        "Softmax-of-log pool (extremization a=#{a}):\n#{lines.join("\n")}"
      end
    when 'numeric', 'discrete'
      keys = forecasts.first.percentiles.keys.sort
      arrays = forecasts.map { |f| keys.map { |k| f.percentiles[k] } }
      pooled = Aggregation.pool_numeric(arrays)
      lines = keys.zip(pooled).map { |k, v| "  Percentile #{k.to_s.rjust(2)}: #{v.round(3)}" }
      "Quantile average:\n#{lines.join("\n")}"
    end
  rescue StandardError => e
    warn "CommentBuilder: mechanical baseline build failed: #{e.message}"
    nil
  end

  def self.load_revision_forecasts(post_id)
    Provider::FORECASTERS.each_with_index.map do |provider, index|
      path = cache_path(post_id, "forecasts/revision.#{index}.json")
      next nil unless File.exist?(path)

      Response.new(provider, json: File.read(path))
    end.compact
  rescue StandardError
    []
  end

  def self.enforce_max_length(comment)
    return comment if comment.length <= MAX_COMMENT_LENGTH

    warn "CommentBuilder: comment exceeds #{MAX_COMMENT_LENGTH} chars (actual: #{comment.length}), truncating…"

    # Split into sections, trim from longest section
    sections = comment.split(SECTION_SEPARATOR)

    # Remove sections from the end until we fit, but always keep Pipeline Overview
    # and Final Forecast
    while comment.length > MAX_COMMENT_LENGTH && sections.size > 2
      # Remove the longest middle section (keep first and last)
      middle = sections[1...-1]
      break if middle.empty?

      _, idx = middle.each_with_index.max_by { |s, _| s.length }
      sections.delete_at(idx + 1) # +1 because middle is offset by 1 from sections
      comment = sections.join(SECTION_SEPARATOR)
    end

    # If still too long, hard truncate
    if comment.length > MAX_COMMENT_LENGTH
      comment = comment[0...MAX_COMMENT_LENGTH - 3] + "..."
    end

    comment
  end
end
