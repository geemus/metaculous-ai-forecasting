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
  # Default models — reference source constants so tests stay in sync
  # ---------------------------------------------------------------------------

  def test_anthropic_default_model
    assert_equal Provider::DEFAULT_MODELS[:anthropic], Provider.new(:anthropic).model
  end

  def test_openai_default_model
    assert_equal Provider::DEFAULT_MODELS[:openai], Provider.new(:openai).model
  end

  # ---------------------------------------------------------------------------
  # Model override
  # ---------------------------------------------------------------------------

  def test_anthropic_model_override
    p = Provider.new(:anthropic, model: 'anthropic/custom-model')
    assert_equal 'anthropic/custom-model', p.model
  end

  def test_openai_model_override
    p = Provider.new(:openai, model: 'openai/custom-model')
    assert_equal 'openai/custom-model', p.model
  end

  # ---------------------------------------------------------------------------
  # FORECASTERS constant
  # ---------------------------------------------------------------------------

  def test_forecasters_order_is_stable
    assert_equal %i[anthropic openai perplexity deepseek], Provider::FORECASTERS
  end
end
