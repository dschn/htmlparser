# frozen_string_literal: true

module HTMLParser
  # Map WHATWG / living-standard parse-error codes to the legacy names used in
  # html5lib/WPT tree-construction `#errors` fixtures.
  #
  # Tokenizer conformance keeps the WHATWG codes on `ParseError#code`. Only the
  # tree harness serializes through these aliases (see `ParseError#to_html5lib`).
  module Html5libTreeErrorNames
    # Majority, non-regressing aliases against the current scripting-off suite.
    ALIASES = {
      "eof-in-text" => "expected-named-closing-tag-but-got-eof",
      "unexpected-null-character" => "invalid-codepoint",
      "control-character-reference" => "illegal-codepoint-for-numeric-entity",
      "missing-semicolon-after-character-reference" => "named-entity-without-semicolon",
      "absence-of-digits-in-numeric-character-reference" => "expected-numeric-entity",
      "unexpected-question-mark-instead-of-tag-name" => "expected-tag-name-but-got-question-mark",
      "unexpected-solidus-in-tag" => "unexpected-character-after-solidus-in-tag",
      "incorrectly-opened-comment" => "expected-dashes-or-doctype",
      "expected-closing-tag-but-got-others" => "unexpected-end-tag"
    }.freeze

    module_function

    def alias_code(code)
      ALIASES.fetch(code.to_s, code.to_s)
    end
  end
end
