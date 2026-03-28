# frozen_string_literal: true

require_relative 'test_helper'

class MetaculusQuestionTest < Minitest::Test
  # ---------------------------------------------------------------------------
  # Fixture helpers
  # ---------------------------------------------------------------------------

  CONTINUOUS_RANGE = (0..200).map { |i| i * 0.5 }.freeze  # 201 pts: 0.0..100.0

  def scaling(open_lower: false, open_upper: false, range_min: 0.0, range_max: 100.0)
    {
      'range_min'         => range_min,
      'range_max'         => range_max,
      'nominal_min'       => range_min,
      'nominal_max'       => range_max,
      'open_lower_bound'  => open_lower,
      'open_upper_bound'  => open_upper,
      'continuous_range'  => (0..200).map { |i| range_min + i * (range_max - range_min) / 200.0 }
    }
  end

  def aggregations(centers: [0.5], forecaster_count: 10, history: [])
    {
      'recency_weighted' => {
        'latest'  => { 'centers' => centers, 'forecaster_count' => forecaster_count,
                       'interval_lower_bounds' => [0.25], 'interval_upper_bounds' => [0.75] },
        'history' => history
      }
    }
  end

  def question_data(type: 'binary', extra_question: {})
    base = {
      'id'         => 1,
      'created_at' => '2024-06-15T12:00:00Z',
      'question'   => {
        'id'                  => 100,
        'type'                => type,
        'title'               => 'Will X happen?',
        'description'         => 'Background context.',
        'resolution_criteria' => 'Resolves YES if X.',
        'fine_print'          => 'Additional fine print.',
        'unit'                => '',
        'options'             => nil,
        'scaling'             => nil,
        'my_forecasts'        => { 'latest' => nil },
        'aggregations'        => aggregations
      }.merge(extra_question)
    }
    base
  end

  def numeric_question_data(open_lower: false, open_upper: false,
                            range_min: 0.0, range_max: 100.0, units: 'units')
    question_data(
      type: 'numeric',
      extra_question: {
        'unit'     => units,
        'scaling'  => scaling(open_lower: open_lower, open_upper: open_upper,
                               range_min: range_min, range_max: range_max),
        'aggregations' => aggregations(centers: [0.5])
      }
    )
  end

  def make_question(**kwargs)
    Metaculus::Question.new(data: question_data(**kwargs))
  end

  def make_numeric(**kwargs)
    Metaculus::Question.new(data: numeric_question_data(**kwargs))
  end

  SAMPLE_PERCENTILES = {
    5  => 10.0, 10 => 20.0, 20 => 30.0, 25 => 35.0,
    30 => 40.0, 40 => 48.0, 50 => 55.0, 60 => 62.0,
    70 => 72.0, 75 => 78.0, 80 => 83.0, 90 => 90.0,
    95 => 94.0
  }.freeze

  # ---------------------------------------------------------------------------
  # Data accessors
  # ---------------------------------------------------------------------------

  def test_title
    assert_equal 'Will X happen?', make_question.title
  end

  def test_background
    assert_equal 'Background context.', make_question.background
  end

  def test_criteria_content_joins_resolution_and_fine_print
    result = make_question.criteria_content
    assert_includes result, 'Resolves YES if X.'
    assert_includes result, 'Additional fine print.'
  end

  def test_criteria_content_handles_nil_fine_print
    q = Metaculus::Question.new(data: question_data(
          extra_question: { 'fine_print' => nil }
        ))
    refute_nil q.criteria_content
  end

  def test_units_returns_unit_string
    q = make_numeric(units: 'kg')
    assert_equal 'kg', q.units
  end

  def test_lower_bound_prefers_nominal_min
    q = make_numeric(range_min: 5.0)
    assert_equal 5.0, q.lower_bound
  end

  def test_upper_bound_prefers_nominal_max
    q = make_numeric(range_max: 200.0)
    assert_equal 200.0, q.upper_bound
  end

  def test_existing_forecast_false_when_latest_nil
    refute make_question.existing_forecast?
  end

  def test_existing_forecast_true_when_latest_present
    q = Metaculus::Question.new(data: question_data(
          extra_question: { 'my_forecasts' => { 'latest' => { 'probability_yes' => 0.6 } } }
        ))
    assert q.existing_forecast?
  end

  def test_post_id_returns_data_id
    assert_equal 1, make_question.post_id
  end

  def test_id_returns_question_id
    assert_equal 100, make_question.id
  end

  # ---------------------------------------------------------------------------
  # continuous_cdf — shape and monotonicity
  # ---------------------------------------------------------------------------

  def test_continuous_cdf_returns_201_values
    q      = make_numeric
    result = q.continuous_cdf(SAMPLE_PERCENTILES.dup)
    assert_equal 201, result.length
  end

  def test_continuous_cdf_values_in_unit_interval
    q      = make_numeric
    result = q.continuous_cdf(SAMPLE_PERCENTILES.dup)
    result.each do |v|
      assert v >= 0.0 && v <= 1.0, "CDF value #{v} outside [0, 1]"
    end
  end

  def test_continuous_cdf_is_monotonically_nondecreasing
    q      = make_numeric
    result = q.continuous_cdf(SAMPLE_PERCENTILES.dup)
    result.each_cons(2) do |a, b|
      assert a <= b + 1e-10, "CDF decreased: #{a} -> #{b}"
    end
  end

  # ---------------------------------------------------------------------------
  # continuous_cdf — boundary behaviour per bound configuration
  # ---------------------------------------------------------------------------

  def test_continuous_cdf_closed_bounds_starts_at_zero
    q      = make_numeric(open_lower: false, open_upper: false)
    result = q.continuous_cdf(SAMPLE_PERCENTILES.dup)
    assert_in_delta 0.0, result.first, 1e-10
  end

  def test_continuous_cdf_closed_bounds_ends_at_one
    q      = make_numeric(open_lower: false, open_upper: false)
    result = q.continuous_cdf(SAMPLE_PERCENTILES.dup)
    assert_in_delta 1.0, result.last, 1e-10
  end

  def test_continuous_cdf_open_lower_starts_above_zero
    q      = make_numeric(open_lower: true, open_upper: false)
    result = q.continuous_cdf(SAMPLE_PERCENTILES.dup)
    assert result.first > 0.0, "Expected first CDF value > 0 for open lower bound"
  end

  def test_continuous_cdf_open_upper_ends_below_one
    q      = make_numeric(open_lower: false, open_upper: true)
    result = q.continuous_cdf(SAMPLE_PERCENTILES.dup)
    assert result.last < 1.0, "Expected last CDF value < 1 for open upper bound"
  end

  def test_continuous_cdf_both_open_starts_above_zero_ends_below_one
    q      = make_numeric(open_lower: true, open_upper: true)
    result = q.continuous_cdf(SAMPLE_PERCENTILES.dup)
    assert result.first > 0.0, "Expected first CDF value > 0 for open lower bound"
    assert result.last  < 1.0, "Expected last CDF value < 1 for open upper bound"
  end

  def test_continuous_cdf_closed_bounds_exact_boundary_values
    # Values exactly at range min/max should be buffered inward
    boundary_percentiles = SAMPLE_PERCENTILES.merge(5 => 0.0, 95 => 100.0)
    q      = make_numeric(open_lower: false, open_upper: false)
    result = q.continuous_cdf(boundary_percentiles)
    assert_equal 201, result.length
    result.each_cons(2) { |a, b| assert a <= b + 1e-10 }
  end

  def test_continuous_cdf_large_range
    q      = make_numeric(open_lower: false, open_upper: false,
                          range_min: 0.0, range_max: 10_000.0)
    large_range_percentiles = {
      5  => 500.0,  10 => 1000.0, 20 => 2000.0, 25 => 2500.0,
      30 => 3000.0, 40 => 4000.0, 50 => 5000.0, 60 => 6000.0,
      70 => 7000.0, 75 => 7500.0, 80 => 8000.0, 90 => 9000.0,
      95 => 9500.0
    }
    result = q.continuous_cdf(large_range_percentiles)
    assert_equal 201, result.length
    result.each_cons(2) { |a, b| assert a <= b + 1e-10 }
  end

  # ---------------------------------------------------------------------------
  # trend
  # ---------------------------------------------------------------------------

  def test_trend_returns_zero_for_empty_history
    q = make_question
    assert_equal 0, q.trend
  end

  def test_trend_returns_zero_for_single_point
    history = [{ 'start_time' => 1_000_000, 'end_time' => 1_001_000, 'centers' => [0.5] }]
    data    = question_data(extra_question: {
                'aggregations' => aggregations(history: history)
              })
    q = Metaculus::Question.new(data: data)
    assert_equal 0, q.trend
  end

  def test_trend_positive_for_increasing_series
    history = [
      { 'start_time' => 1_000_000, 'end_time' => 1_001_000, 'centers' => [0.3] },
      { 'start_time' => 1_002_000, 'end_time' => 1_003_000, 'centers' => [0.5] },
      { 'start_time' => 1_004_000, 'end_time' => 1_005_000, 'centers' => [0.7] }
    ]
    data = question_data(extra_question: {
             'aggregations' => aggregations(history: history)
           })
    q = Metaculus::Question.new(data: data)
    assert q.trend > 0, "Expected positive trend for increasing series"
  end

  def test_trend_negative_for_decreasing_series
    history = [
      { 'start_time' => 1_000_000, 'end_time' => 1_001_000, 'centers' => [0.7] },
      { 'start_time' => 1_002_000, 'end_time' => 1_003_000, 'centers' => [0.5] },
      { 'start_time' => 1_004_000, 'end_time' => 1_005_000, 'centers' => [0.3] }
    ]
    data = question_data(extra_question: {
             'aggregations' => aggregations(history: history)
           })
    q = Metaculus::Question.new(data: data)
    assert q.trend < 0, "Expected negative trend for decreasing series"
  end

  # ---------------------------------------------------------------------------
  # aggregate_content
  # ---------------------------------------------------------------------------

  def test_aggregate_content_binary_shows_median
    q      = make_question(type: 'binary')
    result = q.aggregate_content
    assert_includes result, 'Forecaster Count: 10'
    assert_includes result, 'Median'
  end

  def test_aggregate_content_returns_empty_string_when_no_aggregations
    data = question_data(extra_question: {
             'aggregations' => { 'recency_weighted' => { 'latest' => nil, 'history' => [] } }
           })
    q = Metaculus::Question.new(data: data)
    assert_equal '', q.aggregate_content
  end
end
