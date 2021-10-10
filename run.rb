# frozen_string_literal: true

require_relative "lib/htmlparser"
require_relative "lib/htmlparser/tokenizer"

# FIXME: 13.2.3.5 Preprocessing the input stream
def normalize_newlines(string)
  string = string.scrub # FIXME: utf-8 jank
  string.
    gsub(/\u000d\u000a/, "\u000a").
    gsub("\u000d", "\u000a")
end

html = File.read("test-html/hackernews.html")

input_stream = StringScanner.new(normalize_newlines(html))

class Document
end

# 13.2.6 Tree construction
class TreeConstruction
  def initialize(tokenizer:)
    @tokenizer = tokenizer
    @stack_of_open_elements = []
    @document = Document.new
  end

  def call
    tokenizer.parse do |next_token|
      puts next_token.inspect
    end
  end

  private

  attr_reader :tokenizer
end

tree_construction = TreeConstruction.new(tokenizer: HTMLParser::Tokenizer.new(input_stream))
tree_construction.call
