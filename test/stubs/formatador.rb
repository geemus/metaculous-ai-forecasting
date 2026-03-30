# frozen_string_literal: true
# Stub for the formatador gem (not installed in test environment)

module Formatador
  def self.display(*); end
  def self.display_line(*); end
  def self.new
    obj = Object.new
    def obj.instance_variable_set(*); end
    obj
  end
end
