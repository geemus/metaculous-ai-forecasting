# frozen_string_literal: true

require_relative 'test_helper'

class ResponseModelTest < Minitest::Test
  def response_with(json_data)
    Response.new(:anthropic, json: JSON.generate(json_data))
  end

  def base_json(content: '', model: nil)
    data = { 'choices' => [{ 'message' => { 'content' => content } }] }
    data['model'] = model if model
    data
  end

  def test_model_returns_model_string
    r = response_with(base_json(model: 'claude-opus-4-6'))
    assert_equal 'claude-opus-4-6', r.model
  end

  def test_model_returns_nil_when_absent
    r = response_with(base_json)
    assert_nil r.model
  end

  def test_model_returns_openai_model_string
    r = response_with(base_json(model: 'gpt-4o'))
    assert_equal 'gpt-4o', r.model
  end
end
