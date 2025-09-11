# frozen_string_literal: true

# https://github.com/anthropics/anthropic-cookbook/blob/main/patterns/agents/util.py
# https://ruby-doc.org/3.4.1/String.html#method-i-match
def extract_xml(tag, text)
  match = text.match(%r{<#{tag}>([\s\S]*?)</#{tag}>})
  match[1].strip if match
end

def strip_xml(tag, text)
  text.gsub(%r{<#{tag}>([\s\S]*?)</#{tag}>}, '')
end
