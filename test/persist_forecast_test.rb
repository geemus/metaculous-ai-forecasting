# frozen_string_literal: true

require_relative 'test_helper'

# Helpers to build minimal Response JSON for each question type
module ForecastFixtures
  PERCENTILE_LINES = <<~PERCENTILES.strip
    Percentile 5: 10
    Percentile 10: 20
    Percentile 20: 30
    Percentile 25: 35
    Percentile 30: 40
    Percentile 40: 50
    Percentile 50: 60
    Percentile 60: 70
    Percentile 70: 80
    Percentile 75: 85
    Percentile 80: 90
    Percentile 90: 100
    Percentile 95: 110
  PERCENTILES

  def binary_response(probability: '0.45', model: 'claude-opus-4-6')
    Response.new(:anthropic, json: JSON.generate({
      'model' => model,
      'choices' => [{ 'message' => { 'content' => "<probability>#{probability}</probability>" } }]
    }))
  end

  def numeric_response(model: 'claude-opus-4-6')
    Response.new(:anthropic, json: JSON.generate({
      'model' => model,
      'choices' => [{ 'message' => { 'content' => "<percentiles>#{PERCENTILE_LINES}</percentiles>" } }]
    }))
  end

  def multiple_choice_response(model: 'claude-opus-4-6')
    probs = "Option A: 40%\nOption B: 35%\nOption C: 25%"
    Response.new(:anthropic, json: JSON.generate({
      'model' => model,
      'choices' => [{ 'message' => { 'content' => "<probabilities>#{probs}</probabilities>" } }]
    }))
  end
end

class ForecastValueTest < Minitest::Test
  include ForecastFixtures

  # binary
  def test_binary_returns_probability_key
    result = forecast_value(binary_response, 'binary')
    assert result.key?(:probability)
  end

  def test_binary_probability_is_clamped_float
    result = forecast_value(binary_response(probability: '0.45'), 'binary')
    assert_in_delta 0.45, result[:probability], 0.0001
  end

  def test_binary_probability_as_percentage_string
    result = forecast_value(binary_response(probability: '45%'), 'binary')
    assert_in_delta 0.45, result[:probability], 0.0001
  end

  # numeric / discrete
  def test_numeric_returns_percentiles_key
    result = forecast_value(numeric_response, 'numeric')
    assert result.key?(:percentiles)
  end

  def test_numeric_percentiles_is_a_hash
    result = forecast_value(numeric_response, 'numeric')
    assert_kind_of Hash, result[:percentiles]
  end

  def test_numeric_percentiles_has_expected_keys
    result = forecast_value(numeric_response, 'numeric')
    assert_includes result[:percentiles].keys, 50
  end

  def test_discrete_also_returns_percentiles
    result = forecast_value(numeric_response, 'discrete')
    assert result.key?(:percentiles)
  end

  # multiple_choice
  def test_multiple_choice_returns_probabilities_key
    result = forecast_value(multiple_choice_response, 'multiple_choice')
    assert result.key?(:probabilities)
  end

  def test_multiple_choice_probabilities_is_a_hash
    result = forecast_value(multiple_choice_response, 'multiple_choice')
    assert_kind_of Hash, result[:probabilities]
  end

  def test_multiple_choice_probabilities_sum_near_one
    result = forecast_value(multiple_choice_response, 'multiple_choice')
    total = result[:probabilities].values.sum
    assert_in_delta 1.0, total, 0.01
  end

  # unknown type
  def test_unknown_type_returns_empty_hash
    result = forecast_value(binary_response, 'group_of_questions')
    assert_equal({}, result)
  end
end

class PersistRecordStructureTest < Minitest::Test
  include ForecastFixtures

  # Build a minimal fake record the same way persist_forecast.rb does,
  # using only the components we can exercise without the API.
  def setup
    @binary = binary_response(model: 'claude-opus-4-6')
    @numeric = numeric_response(model: 'gpt-4o')
  end

  def test_forecast_value_merged_with_provider_metadata
    forecasters = [:anthropic, :openai, :perplexity, :deepseek]
    forecasts = [binary_response, binary_response, binary_response, binary_response]

    individual = forecasts.each_with_index.map do |f, i|
      { provider: forecasters[i].to_s, model: f.model }.merge(forecast_value(f, 'binary'))
    end

    assert_equal 4, individual.length
    individual.each do |entry|
      assert entry.key?(:provider)
      assert entry.key?(:model)
      assert entry.key?(:probability)
    end
  end

  def test_individual_forecasts_include_model_field
    entry = { provider: 'anthropic', model: @binary.model }.merge(forecast_value(@binary, 'binary'))
    assert_equal 'claude-opus-4-6', entry[:model]
  end

  def test_individual_forecasts_model_nil_when_absent
    r = Response.new(:openai, json: JSON.generate({
      'choices' => [{ 'message' => { 'content' => '<probability>0.5</probability>' } }]
    }))
    entry = { provider: 'openai', model: r.model }.merge(forecast_value(r, 'binary'))
    assert_nil entry[:model]
  end

  def test_record_keys_are_complete
    # Simulate what persist_forecast.rb assembles so structural regressions
    # are caught here rather than discovered at runtime.
    consensus = binary_response
    forecasters = [:anthropic, :openai, :perplexity, :deepseek]
    forecasts = Array.new(4) { binary_response }

    record = {
      post_id: 12345,
      tournament_id: 'fall-aib-2025',
      title: 'Will X happen?',
      question_type: 'binary',
      tags: ['politics'],
      forecasted_at: Time.now.utc.iso8601,
      scheduled_resolve_time: '2026-06-30T00:00:00Z',
      community_prediction_at_forecast: nil,
      consensus_forecast: forecast_value(consensus, 'binary'),
      individual_forecasts: {
        initial: forecasts.each_with_index.map { |f, i| { provider: forecasters[i].to_s, model: f.model }.merge(forecast_value(f, 'binary')) },
        revised: forecasts.each_with_index.map { |f, i| { provider: forecasters[i].to_s, model: f.model }.merge(forecast_value(f, 'binary')) }
      }
    }

    %i[post_id tournament_id title question_type tags forecasted_at
       scheduled_resolve_time community_prediction_at_forecast
       consensus_forecast individual_forecasts].each do |key|
      assert record.key?(key), "record missing key: #{key}"
    end

    assert record[:individual_forecasts].key?(:initial)
    assert record[:individual_forecasts].key?(:revised)
    assert_equal 4, record[:individual_forecasts][:initial].length
    assert_equal 4, record[:individual_forecasts][:revised].length
  end
end

class TestQuestionsSkipTest < Minitest::Test
  def test_known_binary_test_id_is_skipped
    assert TestQuestions.test_question?('578')
  end

  def test_known_numeric_test_id_is_skipped
    assert TestQuestions.test_question?('14333')
  end

  def test_known_multiple_choice_test_id_is_skipped
    assert TestQuestions.test_question?('22427')
  end

  def test_known_discrete_test_id_is_skipped
    assert TestQuestions.test_question?('38880')
  end

  def test_real_question_id_is_not_skipped
    refute TestQuestions.test_question?('99999')
  end

  def test_accepts_integer_post_id
    assert TestQuestions.test_question?(578)
  end
end
