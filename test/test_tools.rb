# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../lib/tools'

class TestTools < Minitest::Test
  # ── single LR, supporting ───────────────────────────────────────────────
  def test_bayesian_update_single_lr_supporting
    result = Tools.bayesian_update({ 'prior' => 0.2, 'likelihood_ratios' => [3] })
    assert_in_delta 0.428571, result[:posterior], 0.0001
    assert_equal 'supporting', result[:direction]
    assert_equal 1, result[:evidence_count]
    assert_in_delta 3.0, result[:combined_likelihood_ratio], 0.0001
  end

  # ── single LR, opposing ─────────────────────────────────────────────────
  def test_bayesian_update_single_lr_opposing
    result = Tools.bayesian_update({ 'prior' => 0.5, 'likelihood_ratios' => [0.25] })
    assert_in_delta 0.2, result[:posterior], 0.0001
    assert_equal 'opposing', result[:direction]
    assert_equal 1, result[:evidence_count]
    assert_in_delta 0.25, result[:combined_likelihood_ratio], 0.0001
  end

  # ── multiple independent LRs ────────────────────────────────────────────
  def test_bayesian_update_multiple_independent_lrs
    result = Tools.bayesian_update({ 'prior' => 0.1, 'likelihood_ratios' => [5, 2] })
    assert_in_delta 0.526316, result[:posterior], 0.0001
    assert_equal 'supporting', result[:direction]
    assert_equal 2, result[:evidence_count]
    assert_in_delta 10.0, result[:combined_likelihood_ratio], 0.0001
  end

  # ── neutral evidence (LR=1) ─────────────────────────────────────────────
  def test_bayesian_update_neutral_evidence
    result = Tools.bayesian_update({ 'prior' => 0.7, 'likelihood_ratios' => [1] })
    assert_in_delta 0.7, result[:posterior], 0.0001
    assert_equal 'neutral', result[:direction]
    assert_equal 0, result[:shift_magnitude]
  end

  # ── evidence_items mode ─────────────────────────────────────────────────
  def test_bayesian_update_evidence_items_mode
    result = Tools.bayesian_update({
                                    'prior' => 0.3,
                                    'evidence_items' => [
                                      { 'p_e_given_h' => 0.8, 'p_e_given_not_h' => 0.2 }
                                    ]
                                  })
    # LR = 0.8 / 0.2 = 4
    assert_in_delta 0.631579, result[:posterior], 0.0001
    assert_equal 'supporting', result[:direction]
    assert_equal 1, result[:evidence_count]
    assert_in_delta 4.0, result[:combined_likelihood_ratio], 0.0001
  end

  # ── both modes combined ─────────────────────────────────────────────────
  def test_bayesian_update_both_modes_combined
    result = Tools.bayesian_update({
                                    'prior' => 0.5,
                                    'likelihood_ratios' => [3],
                                    'evidence_items' => [
                                      { 'p_e_given_h' => 0.9, 'p_e_given_not_h' => 0.3 }
                                    ]
                                  })
    # evidence_items LR = 0.9 / 0.3 = 3, combined = 3 * 3 = 9
    # posterior = 0.5 * 9 / (0.5 * 9 + 0.5) = 4.5 / 5.0 = 0.9
    assert_in_delta 0.9, result[:posterior], 0.0001
    assert_equal 2, result[:evidence_count]
    assert_in_delta 9.0, result[:combined_likelihood_ratio], 0.0001
  end

  # ── prior zero clamped ──────────────────────────────────────────────────
  def test_bayesian_update_prior_zero_clamped
    result = Tools.bayesian_update({ 'prior' => 0, 'likelihood_ratios' => [10] })
    assert result[:posterior] > 0, 'posterior should be > 0 (clamped)'
    assert result[:posterior] < 0.5, 'posterior should be small'
    refute result[:posterior].nan?
  end

  # ── prior one clamped ───────────────────────────────────────────────────
  def test_bayesian_update_prior_one_clamped
    result = Tools.bayesian_update({ 'prior' => 1, 'likelihood_ratios' => [0.1] })
    assert result[:posterior] < 1, 'posterior should be < 1 (clamped)'
    assert result[:posterior] > 0.5, 'posterior should be near 1'
    refute result[:posterior].nan?
  end

  # ── very strong evidence ────────────────────────────────────────────────
  def test_bayesian_update_very_strong_evidence
    result = Tools.bayesian_update({ 'prior' => 0.01, 'likelihood_ratios' => [1000] })
    assert_in_delta 0.909918, result[:posterior], 0.001
    assert_equal 'supporting', result[:direction]
    assert result[:shift_magnitude] > 0.5
  end

  # ── very weak evidence ──────────────────────────────────────────────────
  def test_bayesian_update_very_weak_evidence
    result = Tools.bayesian_update({ 'prior' => 0.99, 'likelihood_ratios' => [0.001] })
    assert_in_delta 0.090164, result[:posterior], 0.001
    assert_equal 'opposing', result[:direction]
    assert result[:shift_magnitude] > 0.5
  end

  # ── raises on empty evidence ────────────────────────────────────────────
  def test_bayesian_update_raises_on_empty_evidence
    assert_raises(ArgumentError) do
      Tools.bayesian_update({ 'prior' => 0.5 })
    end
    assert_raises(ArgumentError) do
      Tools.bayesian_update({ 'prior' => 0.5, 'likelihood_ratios' => [] })
    end
  end

  # ── raises on negative LR ───────────────────────────────────────────────
  def test_bayesian_update_allows_fractional_lr
    result = Tools.bayesian_update({ 'prior' => 0.5, 'likelihood_ratios' => [0.5] })
    assert_in_delta 0.333333, result[:posterior], 0.0001
  end

  # ── raises on prior out of range ────────────────────────────────────────
  def test_bayesian_update_raises_on_prior_out_of_range
    assert_raises(ArgumentError) do
      Tools.bayesian_update({ 'prior' => -0.1, 'likelihood_ratios' => [2] })
    end
    assert_raises(ArgumentError) do
      Tools.bayesian_update({ 'prior' => 1.5, 'likelihood_ratios' => [2] })
    end
  end

  # ── raises on zero P(E|¬H) ──────────────────────────────────────────────
  def test_bayesian_update_raises_on_zero_p_e_given_not_h
    assert_raises(ArgumentError) do
      Tools.bayesian_update({
                              'prior' => 0.5,
                              'evidence_items' => [
                                { 'p_e_given_h' => 0.8, 'p_e_given_not_h' => 0 }
                              ]
                            })
    end
  end

  # ── dispatch routes to bayesian_update ──────────────────────────────────
  def test_dispatch_routes_bayesian_update
    tool_call = {
      'function' => {
        'name' => 'bayesian_update',
        'arguments' => JSON.generate({ 'prior' => 0.2, 'likelihood_ratios' => [3] })
      }
    }
    result = Tools.dispatch(tool_call)
    parsed = JSON.parse(result)
    assert_in_delta 0.428571, parsed['posterior'], 0.0001
    assert_equal 'supporting', parsed['direction']
  end

  # ── dispatch still routes to calculate ──────────────────────────────────
  def test_dispatch_still_routes_calculate
    tool_call = {
      'function' => {
        'name' => 'calculate',
        'arguments' => JSON.generate({ 'expression' => '2 + 3' })
      }
    }
    result = Tools.dispatch(tool_call)
    assert_equal '5', result
  end

  # ── shift magnitude is absolute difference ──────────────────────────────
  def test_shift_magnitude_is_absolute_difference
    result = Tools.bayesian_update({ 'prior' => 0.3, 'likelihood_ratios' => [4] })
    expected_shift = (result[:posterior] - 0.3).abs
    assert_equal expected_shift, result[:shift_magnitude]
  end

  # ── prior is preserved in output ────────────────────────────────────────
  def test_prior_preserved_in_output
    result = Tools.bayesian_update({ 'prior' => 0.33, 'likelihood_ratios' => [2] })
    assert_equal 0.33, result[:prior]
  end
end
