# frozen_string_literal: true

require_relative "htmlparser/version"
require_relative "htmlparser/input"
require_relative "htmlparser/tokens"
require_relative "htmlparser/parse_error"
require_relative "htmlparser/tokenizer"
require_relative "htmlparser/tree_construction"

module HTMLParser
  TokenizeResult = Struct.new(:tokens, :parse_errors)

  # Tokenize an HTML string. Used by specs and html5lib harnesses.
  # content_model maps to the initial tokenizer state (data, rcdata, …).
  # last_start_tag is the tag name of the last emitted start tag (html5lib lastStartTag).
  def self.tokenize(html, content_model: :data, last_start_tag: nil)
    parse_errors = []
    input_stream = InputStream.new(html)
    tokenizer = Tokenizer.new(
      input_stream,
      content_model: content_model,
      last_start_tag: last_start_tag,
      parse_errors: parse_errors
    )
    tokens = []
    tokenizer.parse { |token| tokens << token }
    TokenizeResult.new(tokens: tokens, parse_errors: parse_errors)
  end

  # Run the (currently stub) tree construction stage over tokenized input.
  def self.parse(html, &)
    input_stream = InputStream.new(html)
    tokenizer = Tokenizer.new(input_stream)
    TreeConstruction.new(tokenizer: tokenizer).call(&)
  end
end
