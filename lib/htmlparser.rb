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

  # Run tree construction over tokenized input (full document).
  def self.parse(html, &)
    input_stream = InputStream.new(html)
    tokenizer = Tokenizer.new(input_stream)
    TreeConstruction.new(tokenizer: tokenizer).call(&)
  end

  # §13.4 HTML fragment parsing algorithm.
  # context is an html5lib context string: "div", "td", "svg path", "math mi", …
  def self.parse_fragment(html, context:, scripting: false, &)
    context_element = context_element_for_fragment(context)
    content_model = content_model_for_fragment_context(context_element, scripting: scripting)
    input_stream = InputStream.new(html)
    tokenizer = Tokenizer.new(
      input_stream,
      content_model: content_model,
      last_start_tag: context_element.name
    )
    TreeConstruction.new(tokenizer: tokenizer, context_element: context_element).call(&)
  end

  def self.context_element_for_fragment(context)
    parts = context.to_s.split
    if parts.length == 2 && parts[0] == "svg"
      Element.new(parts[1], namespace: SVG_NAMESPACE)
    elsif parts.length == 2 && parts[0] == "math"
      Element.new(parts[1], namespace: MATHML_NAMESPACE)
    else
      Element.new(parts.fetch(0))
    end
  end
  private_class_method :context_element_for_fragment

  def self.content_model_for_fragment_context(element, scripting: false)
    return :data unless element.html?

    case element.name
    when "title", "textarea" then :rcdata
    when "style", "xmp", "iframe", "noembed", "noframes" then :rawtext
    when "script" then :script_data
    when "noscript" then scripting ? :rawtext : :data
    when "plaintext" then :plaintext
    else :data
    end
  end
  private_class_method :content_model_for_fragment_context
end
