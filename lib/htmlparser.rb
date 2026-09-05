# frozen_string_literal: true

require_relative "htmlparser/version"
require_relative "htmlparser/input"
require_relative "htmlparser/encoding"
require_relative "htmlparser/encoding/prescan"
require_relative "htmlparser/tokens"
require_relative "htmlparser/parse_error"
require_relative "htmlparser/tokenizer"
require_relative "htmlparser/tree_construction"

module HTMLParser
  TokenizeResult = Struct.new(:tokens, :parse_errors)

  # §13.2.3 — sniff encoding from a byte string (BOM, then meta prescan, then default).
  def self.sniff_encoding(bytes, default: "windows-1252")
    Encoding.sniff(bytes, default: default)
  end

  # Parse a byte document: sniff (unless `encoding:` given), decode, tree-build.
  # Retries when §13.2.3.3 change-the-encoding fires (tentative confidence only).
  def self.parse_bytes(bytes, encoding: nil, confidence: nil, default: "windows-1252", &)
    raw = bytes.to_str.b
    chosen = encoding
    conf = confidence

    loop do
      sniff = if chosen
        name = Encoding.get_encoding(chosen) || chosen.to_s
        Encoding::SniffResult.new(name: name, confidence: conf || :certain)
      else
        Encoding.sniff(raw, default: default)
      end

      begin
        return parse_unicode(
          Encoding.decode(raw, sniff.name),
          character_encoding: sniff.name,
          encoding_confidence: sniff.confidence,
          &
        )
      rescue EncodingChanged => e
        chosen = e.new_encoding
        conf = :certain
      end
    end
  end

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
    parse_unicode(html, &)
  end

  def self.parse_unicode(html, character_encoding: nil, encoding_confidence: nil, &)
    input_stream = InputStream.new(html)
    tokenizer = Tokenizer.new(input_stream)
    TreeConstruction.new(
      tokenizer: tokenizer,
      character_encoding: character_encoding,
      encoding_confidence: encoding_confidence
    ).call(&)
  end
  private_class_method :parse_unicode

  # §13.4 HTML fragment parsing algorithm.
  # context is an html5lib context string: "div", "td", "svg path", "math mi", …
  def self.parse_fragment(html, context:, scripting: false, &)
    context_element = context_element_for_fragment(context)
    content_model = content_model_for_fragment_context(context_element, scripting: scripting)
    input_stream = InputStream.new(html)
    # §13.4 — no start tag has been emitted, so there is no appropriate end tag in the
    # fragment case (RCDATA/RAWTEXT/script end tags are treated as text).
    tokenizer = Tokenizer.new(input_stream, content_model: content_model)
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
