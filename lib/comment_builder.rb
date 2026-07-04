# frozen_string_literal: true

module CommentBuilder
  MAX_COMMENT_LENGTH = 10_000

  module_function

  def build_pipeline_comment(post_id, question, consensus_response, revised_forecasts)
    baseline = begin
      mechanical_baseline(question, revised_forecasts)
    rescue StandardError
      nil
    end

    sections = [
      build_pipeline_overview(post_id, question, baseline),
      build_news_summary(post_id),
      build_research_summary(post_id),
      build_forecaster_positions(question, revised_forecasts),
      build_consensus_analysis(consensus_response),
      build_final_forecast(question, consensus_response)
    ]

    comment = sections.join("\n\n---\n\n")
    truncate_if_needed(comment)
  end

  # ─── Pipeline Overview ───────────────────────────────────────────────

  def build_pipeline_overview(post_id, question, baseline)
    news_meta = news_metadata(post_id)

    lines = []
    lines << '## Pipeline Overview'
    lines << "- **Question**: #{question.title}"
    lines << "- **Type**: #{question.type}"
    lines << "- **Post ID**: #{post_id}"
    lines << '- **Stages**: News → Research → 4 Forecasters → Delphi Revise → Consensus'
    lines << "- **News**: #{news_meta}" if news_meta
    lines << "- **Mechanical Baseline**: #{baseline.split("\n").first}" if baseline
    lines.join("\n")
  end

  # ─── News Summary ────────────────────────────────────────────────────

  def build_news_summary(post_id)
    summary_path = cache_path(post_id, 'outputs/news_summary.md')

    content = if File.exist?(summary_path)
                File.read(summary_path).strip
              else
                fallback_news_summary(post_id)
              end

    content = '_No news summary available._' if content.nil? || content.empty?

    "## News Summary\n#{content}"
  end

  def fallback_news_summary(post_id)
    news_path = cache_path(post_id, 'news.json')
    return nil unless File.exist?(news_path)

    news = JSON.parse(File.read(news_path))
    articles = news['as_dicts'] || []
    return nil if articles.empty?

    dates = articles.map { |a| a['pub_date'] }.compact.sort
    date_range = if dates.any?
                   "#{dates.first[0..9]} to #{dates.last[0..9]}"
                 else
                   'unknown date range'
                 end

    top_titles = articles.first(3).map { |a| "- #{a['eng_title']}" }.join("\n")

    "#{articles.length} articles (#{date_range}). Top 3 by relevance:\n#{top_titles}"
  rescue StandardError
    nil
  end

  # ─── Research Summary ────────────────────────────────────────────────

  def build_research_summary(post_id)
    research_path = cache_path(post_id, 'research.json')

    unless File.exist?(research_path)
      return "## Research Summary\n_No research data available._"
    end

    research_json = File.read(research_path)
    research = Response.new(:open_router, json: research_json)
    summary = research.extracted_content('research_summary')

    if summary && !summary.empty?
      return "## Research Summary\n#{summary}"
    end

    # Fallback: extract ### 1-4 sections into bullet points
    fallback = fallback_research_summary(research.content)
    "## Research Summary\n#{fallback || '_Could not extract research summary._'}"
  rescue StandardError => e
    "## Research Summary\n_Error loading research: #{e.message}_"
  end

  def fallback_research_summary(content)
    return nil if content.nil? || content.empty?

    sections = content.scan(/^###\s+\d+\.?\s*(.+?)\n((?:(?!^###\s).*\n?)*)/)
    return nil if sections.empty?

    bullets = sections.first(4).map do |heading, body|
      # Truncate each section body to first 2 sentences
      sentences = body.strip.split(/(?<=[.!?])\s+/)
      truncated = sentences.first(2).join(' ').strip
      truncated = truncated[0..200] if truncated.length > 200
      "- **#{heading.strip}**: #{truncated}"
    end

    "_Automatically extracted from research sections (research_summary tag missing):_\n#{bullets.join("\n")}"
  rescue StandardError
    nil
  end

  # ─── Forecaster Positions ────────────────────────────────────────────

  def build_forecaster_positions(question, forecasts)
    header = '| Provider | Forecast | Confidence | Key Argument |'
    separator = '|----------|----------|------------|-------------|'

    rows = forecasts.map do |forecast|
      provider = forecast.provider.to_s.capitalize
      value = format_forecast_value(question, forecast)
      confidence = forecast.extracted_content('confidence') || 'N/A'
      argument = forecast.extracted_content('forecast_summary')

      # Fallback to first sentence of think if forecast_summary is missing
      if argument.nil? || argument.empty?
        think = forecast.extracted_content('think')
        argument = if think && !think.empty?
                     first_sentence = think.split(/(?<=[.!?])\s+/).first
                     first_sentence.to_s.strip[0..150]
                   else
                     # Last resort: first sentence of non-tag content
                     stripped = forecast.stripped_content('think', 'forecast_summary', 'confidence',
                                                          'probability', 'percentiles', 'probabilities',
                                                          'calibration_disclaimer')
                     first_sentence = stripped.split(/(?<=[.!?])\s+/).first
                     first_sentence.to_s.strip[0..150]
                   end
      end

      argument = argument.to_s.strip[0..150]
      argument = argument.gsub("\n", ' ') # Flatten newlines for table cell
      argument = '_No argument available_' if argument.empty?

      "| #{provider} | #{value} | #{confidence} | #{argument} |"
    end

    ["## Forecaster Positions", header, separator, *rows].join("\n")
  end

  def format_forecast_value(question, forecast)
    case question.type
    when 'binary'
      pct = (forecast.probability * 100).round(1)
      "#{pct}%"
    when 'numeric', 'discrete'
      percentiles = forecast.percentiles
      p50 = percentiles[50]
      units = question.units.to_s.empty? ? '' : " #{question.units}"
      "#{p50}#{units}"
    when 'multiple_choice'
      probs = forecast.probabilities
      top = probs.max_by { |_k, v| v }
      "#{top[0]}: #{(top[1] * 100).round(1)}%"
    else
      'N/A'
    end
  rescue StandardError
    'N/A'
  end

  # ─── Consensus Analysis ──────────────────────────────────────────────

  def build_consensus_analysis(consensus_response)
    think = consensus_response.extracted_content('think')

    content = if think && !think.empty?
                think
              else
                # Fall back to stripped content (entire response minus XML tags)
                consensus_response.stripped_content('think')
              end

    content = '_No analysis available._' if content.nil? || content.strip.empty?

    "## Consensus Analysis\n#{content.strip}"
  end

  # ─── Final Forecast ──────────────────────────────────────────────────

  def build_final_forecast(question, consensus_response)
    content = consensus_response.content

    xml_block = case question.type
                when 'binary'
                  extract_xml_block(content, 'probability')
                when 'numeric', 'discrete'
                  extract_xml_block(content, 'percentiles')
                when 'multiple_choice'
                  extract_xml_block(content, 'probabilities')
                end

    forecast_text = if xml_block
                      xml_block.strip
                    else
                      '_Forecast value not found in response._'
                    end

    "## Final Forecast\n#{forecast_text}"
  end

  # ─── Helpers ─────────────────────────────────────────────────────────

  def news_metadata(post_id)
    news_path = cache_path(post_id, 'news.json')
    return nil unless File.exist?(news_path)

    news = JSON.parse(File.read(news_path))
    articles = news['as_dicts'] || []
    return nil if articles.empty?

    dates = articles.map { |a| a['pub_date'] }.compact.sort
    if dates.any?
      "#{articles.length} articles (#{dates.first[0..9]} to #{dates.last[0..9]})"
    else
      "#{articles.length} articles"
    end
  rescue StandardError
    nil
  end

  def extract_xml_block(text, tag)
    match = text.match(%r{<#{tag}>[\s\S]*?</#{tag}>})
    match&.[](0)
  end

  def truncate_if_needed(comment)
    return comment if comment.length <= MAX_COMMENT_LENGTH

    # Try to keep: overview, forecaster table, and final forecast intact.
    # Trim news summary, research summary, and consensus analysis.
    sections = comment.split(/\n\n---\n\n/)
    return comment if sections.length < 4

    # Section order: [0] Overview, [1] News, [2] Research, [3] Forecaster,
    #                [4] Consensus Analysis, [5] Final Forecast

    # Progressively trim middle sections until we're under the limit
    trim_order = [1, 2, 4] # news, research, consensus — trim in this order

    trim_order.each do |idx|
      break if sections.join("\n\n---\n\n").length <= MAX_COMMENT_LENGTH
      next unless sections[idx]

      # Truncate the section to just its header + first line
      lines = sections[idx].split("\n")
      header = lines[0]
      first_content = lines[1..].find { |l| !l.strip.empty? && !l.start_with?('|') && !l.start_with?('-') }
      sections[idx] = if first_content
                        "#{header}\n#{first_content.strip[0..200]}...\n_(truncated for length)_"
                      else
                        "#{header}\n_(truncated for length)_"
                      end
    end

    # If still too long, hard truncate
    result = sections.join("\n\n---\n\n")
    if result.length > MAX_COMMENT_LENGTH
      result = result[0...MAX_COMMENT_LENGTH - 50] + "\n\n...\n_(comment truncated to fit length limit)_"
    end

    result
  end
end
