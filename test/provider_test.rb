# frozen_string_literal: true

require_relative 'test_helper'

class ProviderTest < Minitest::Test
  # ---------------------------------------------------------------------------
  # Factory — correct class instantiation
  # ---------------------------------------------------------------------------

  def test_anthropic_instantiates_open_router
    assert_instance_of OpenRouter, Provider.new(:anthropic)
  end

  def test_openai_instantiates_open_router
    assert_instance_of OpenRouter, Provider.new(:openai)
  end

  def test_perplexity_instantiates_perplexity
    assert_instance_of Perplexity, Provider.new(:perplexity)
  end

  def test_deepseek_instantiates_deepseek
    assert_instance_of DeepSeek, Provider.new(:deepseek)
  end

  def test_unknown_provider_raises_argument_error
    assert_raises(ArgumentError) { Provider.new(:unknown) }
  end

  # ---------------------------------------------------------------------------
  # Default models
  # ---------------------------------------------------------------------------

  def test_anthropic_default_model
    assert_equal 'anthropic/claude-opus-4.6', Provider.new(:anthropic).model
  end

  def test_openai_default_model
    assert_equal 'openai/gpt-5.4', Provider.new(:openai).model
  end

  # ---------------------------------------------------------------------------
  # Model override
  # ---------------------------------------------------------------------------

  def test_anthropic_model_override
    assert_equal 'anthropic/custom-model', Provider.new(:anthropic, model: 'anthropic/custom-model').model
  end

  def test_openai_model_override
    assert_equal 'openai/custom-model', Provider.new(:openai, model: 'openai/custom-model').model
  end

  # ---------------------------------------------------------------------------
  # FORECASTERS constant
  # ---------------------------------------------------------------------------

  def test_forecasters_has_four_entries
    assert_equal 4, Provider::FORECASTERS.length
  end

  def test_forecasters_contains_expected_providers
    assert_includes Provider::FORECASTERS, :anthropic
    assert_includes Provider::FORECASTERS, :openai
    assert_includes Provider::FORECASTERS, :perplexity
    assert_includes Provider::FORECASTERS, :deepseek
  end

  def test_forecasters_order_is_stable
    assert_equal %i[anthropic openai perplexity deepseek], Provider::FORECASTERS
  end

  def test_forecasters_is_frozen
    assert Provider::FORECASTERS.frozen?
  end
end
