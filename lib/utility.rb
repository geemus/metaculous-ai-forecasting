# frozen_string_literal: true

def cache(question_id, path, &block)
  tmp_path = "./tmp/#{question_id}/#{path}"
  if File.exist?(tmp_path)
    Formatador.display_line "[light_green](Cache @ `#{tmp_path})[/]`"
    File.read(tmp_path)
  else
    data = block.call
    File.write(tmp_path, data)
    Formatador.display_line "[light_green](Cached @ `#{tmp_path})[/]`"
    data
  end
end

# https://github.com/anthropics/anthropic-cookbook/blob/main/patterns/agents/util.py
# https://ruby-doc.org/3.4.1/String.html#method-i-match
def extract_xml(tag, text)
  match = text.match(%r{<#{tag}>([\s\S]*?)</#{tag}>})
  match[1].strip if match
end

def strip_xml(tag, text)
  text.gsub(%r{<#{tag}>([\s\S]*?)</#{tag}>}, '').strip
end
