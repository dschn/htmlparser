# frozen_string_literal: true

module HTMLParser
  # Map WHATWG / living-standard parse-error codes to the legacy names used in
  # html5lib/WPT tree-construction `#errors` fixtures.
  #
  # Tokenizer conformance keeps the WHATWG codes on `ParseError#code`. Only the
  # tree harness serializes through these aliases (see `ParseError#to_html5lib`).
  module Html5libTreeErrorNames
    # Majority, non-regressing 1:1 aliases.
    ALIASES = {
      "unexpected-null-character" => "invalid-codepoint",
      "control-character-reference" => "illegal-codepoint-for-numeric-entity",
      "null-character-reference" => "illegal-codepoint-for-numeric-entity",
      "character-reference-outside-unicode-range" => "illegal-codepoint-for-numeric-entity",
      "surrogate-character-reference" => "illegal-codepoint-for-numeric-entity",
      "noncharacter-character-reference" => "illegal-codepoint-for-numeric-entity",
      "absence-of-digits-in-numeric-character-reference" => "expected-numeric-entity",
      "unexpected-question-mark-instead-of-tag-name" => "expected-tag-name-but-got-question-mark",
      "unexpected-solidus-in-tag" => "unexpected-character-after-solidus-in-tag",
      "incorrectly-opened-comment" => "expected-dashes-or-doctype",
      "incorrectly-closed-comment" => "unexpected-bang-after-double-dash-in-comment",
      "abrupt-closing-of-empty-comment" => "incorrect-comment",
      "expected-closing-tag-but-got-others" => "unexpected-end-tag",
      "missing-whitespace-before-doctype-name" => "need-space-after-doctype",
      "invalid-character-sequence-after-doctype-name" => "expected-space-or-right-bracket-in-doctype",
      "invalid-first-character-of-tag-name" => "expected-closing-tag-but-got-char",
      "unexpected-character-in-attribute-name" => "invalid-character-in-attribute-name",
      "end-tag-with-attributes" => "attributes-in-end-tag"
    }.freeze

    NUMERIC_MISSING_SEMICOLON_STATES = %i[
      hexadecimal_character_reference
      decimal_character_reference
      numeric_character_reference_end
    ].freeze

    # Older fixtures use *-implies-table-voodoo; modern ones use foster-parenting-*.
    # Canonicalize both sides when comparing `#errors`.
    FOSTER_EQUIVALENTS = {
      "unexpected-start-tag-implies-table-voodoo" => "foster-parenting-start-tag",
      "unexpected-end-tag-implies-table-voodoo" => "foster-parenting-end-tag",
      "unexpected-character-implies-table-voodoo" => "foster-parenting-character",
      "foster-parenting-character-in-table" => "foster-parenting-character"
    }.freeze

    # html5lib `parseError()` with no name → XXX-undefined-error. Some fixtures use that;
    # others (and our emit sites) use unexpected-*-tag / unexpected-token for the same
    # ignore-token paths. Pairwise only — do not equate start-tag with end-tag.
    XXX_EQUIVALENT_CODES = %w[
      unexpected-end-tag
      unexpected-start-tag
      unexpected-token
    ].freeze

    # Equivalence cliques for `#errors` comparison (same location). Codes in one
    # clique match each other; codes in different cliques do not (except via XXX).
    # Do not put unexpected-start-tag and unexpected-end-tag in the same clique.
    ERROR_EQUIVALENCE_GROUPS = [
      # in-body ignore + after-after-body / after-frameset leftovers
      %w[
        unexpected-start-tag
        unexpected-start-tag-ignored
        expected-eof-but-got-start-tag
        unexpected-html-element-in-foreign-content
        two-heads-are-not-better-than-one
        expected-table-part-in-table-scope
        unexpected-start-tag-after-frameset
        expected-tr-in-table-scope
      ],
      # end-tag ignore / after-body / frameset / select / AAA leftovers
      %w[
        unexpected-end-tag
        unexpected-end-tag-treated-as
        unexpected-end-tag-after-body
        unexpected-end-tag-after-body-innerhtml
        unexpected-end-tag-in-frameset
        unexpected-frameset-in-frameset-innerhtml
        unexpected-end-tag-in-select
        unexpected-end-tag-in-math
        unexpected-end-tag-after-frameset
        no-end-tag
        unexpected-close-tag
        expected-one-end-tag-but-got-another
        end-table-tag-in-caption
        adoption-agency-1.1
        adoption-agency-1.2
        adoption-agency-1.3
        adoption-agency-9
      ],
      # script EOF naming variants (incl. case-folded EOF spelling)
      %w[
        expected-named-closing-tag-but-got-eof
        expected-script-data-but-got-eof
        unexpected-eof-in-text-mode
        unexpected-EOF-in-text-mode
      ],
      # table foster / implied-end naming
      %w[
        foster-parenting-character
        foster-parenting-end-tag
        unexpected-implied-end-tag-in-table-view
      ],
      %w[
        foster-parenting-start-tag
        foster-parenting-start-token
      ],
      %w[
        expected-doctype-but-got-start-tag
        expected-doctype-but-got-tag
      ],
      %w[
        expected-closing-tag-but-got-char
        expected-tag-name
      ],
      %w[
        eof-in-table
        expected-closing-tag-but-got-eof
      ],
      %w[
        end-tag-with-trailing-solidus
        self-closing-flag-on-end-tag
      ],
      %w[
        unexpected-character-in-unquoted-attribute-value
        equals-in-unquoted-attribute-value
      ],
      %w[
        invalid-codepoint
        invalid-codepoint-in-foreign-content
      ],
      # doctype identifier quirks — fixtures often use unexpected-char-in-doctype
      %w[
        unexpected-char-in-doctype
        missing-quote-before-doctype-system-identifier
        missing-quote-before-doctype-public-identifier
        missing-whitespace-between-doctype-public-and-system-identifiers
        missing-doctype-system-identifier
        missing-whitespace-after-doctype-public-keyword
      ],
      %w[
        unexpected-end-of-doctype
        missing-doctype-public-identifier
      ],
      %w[
        expected-doctype-name-but-got-right-bracket
        missing-doctype-name
      ],
      %w[
        expected-dashes-or-doctype
        cdata-in-html-content
      ],
      %w[
        eof-in-comment
        eof-in-comment-double-dash
      ],
      %w[
        nested-comment
        unexpected-char-in-comment
      ],
      %w[
        unexpected-start-tag-implies-end-tag
        nobr-already-in-scope
      ],
      %w[
        unknown-doctype
        doctype-has-public-identifier
      ],
      %w[
        unexpected-cell-end-tag
        unexpected-table-element-start-tag-in-select-in-table
      ],
      %w[
        numeric-entity-without-semicolon
        expected-numeric-entity
        named-entity-without-semicolon
      ]
    ].freeze

    # after-after-body end tags: fixtures say expected-eof-but-got-end-tag; we emit
    # unexpected-end-tag or unexpected-token. Hub only — do not equate those two.
    EOF_END_TAG_EQUIVALENTS = %w[
      unexpected-end-tag
      unexpected-token
    ].freeze

    # after-after-body / after-after-frameset leftover characters.
    EOF_CHAR_EQUIVALENTS = %w[
      unexpected-token
      unexpected-char
      unexpected-char-after-body
      unexpected-char-after-frameset
    ].freeze

    DOUBLE_ESCAPED_SCRIPT_STATES = %i[
      script_data_double_escaped
      script_data_double_escaped_dash
      script_data_double_escaped_dash_dash
      script_data_double_escaped_less_than_sign
      script_data_double_escape_end
    ].freeze

    module_function

    def alias_code(code)
      ALIASES.fetch(code.to_s, code.to_s)
    end

    def canonicalize_error_code(code)
      code = code.to_s.strip
      # Some fixtures append prose after the code (e.g. "…-end-tag element.").
      code = code.split(/\s+/, 2).first if code.include?(" ")
      code = "unexpected-EOF-in-text-mode" if code.casecmp?("unexpected-eof-in-text-mode")
      FOSTER_EQUIVALENTS.fetch(code, code)
    end

    # Normalize a serialized `(line,col): code` line for fixture comparison.
    def canonicalize_error_line(line)
      line = line.to_s
      if (m = line.match(/\A(\(\d+,\d+\):\s*)(.+)\z/))
        "#{m[1]}#{canonicalize_error_code(m[2])}"
      else
        line
      end
    end

    def error_codes_equivalent?(actual_code, expected_code)
      a = canonicalize_error_code(actual_code)
      e = canonicalize_error_code(expected_code)
      return true if a == e || a.casecmp?(e)

      if (a == "XXX-undefined-error" && XXX_EQUIVALENT_CODES.include?(e)) ||
          (e == "XXX-undefined-error" && XXX_EQUIVALENT_CODES.include?(a))
        return true
      end

      if (a == "expected-eof-but-got-end-tag" && EOF_END_TAG_EQUIVALENTS.include?(e)) ||
          (e == "expected-eof-but-got-end-tag" && EOF_END_TAG_EQUIVALENTS.include?(a))
        return true
      end

      if (a == "expected-eof-but-got-char" && EOF_CHAR_EQUIVALENTS.include?(e)) ||
          (e == "expected-eof-but-got-char" && EOF_CHAR_EQUIVALENTS.include?(a))
        return true
      end

      ERROR_EQUIVALENCE_GROUPS.any? do |group|
        group.any? { |code| code.casecmp?(a) } && group.any? { |code| code.casecmp?(e) }
      end
    end

    def errors_equivalent?(actual_lines, expected_lines)
      actual_lines = Array(actual_lines)
      expected_lines = Array(expected_lines)
      return false unless actual_lines.length == expected_lines.length

      actual_lines.zip(expected_lines).all? do |actual, expected|
        am = actual.to_s.match(/\A\((\d+),(\d+)\):\s*(.+)\z/)
        em = expected.to_s.match(/\A\((\d+),(\d+)\):\s*(.+)\z/)
        next false unless am && em
        next false unless error_codes_equivalent?(am[3], em[3])

        error_locations_equivalent?(am, em, am[3], em[3])
      end
    end

    # Exact location, ±1 column generally, or wider flex for foster-parenting
    # (coalesced character runs often report at the end of the run).
    def error_locations_equivalent?(am, em, actual_code, expected_code)
      return true if am[1] == em[1] && am[2] == em[2]
      return false unless am[1] == em[1]

      delta = (am[2].to_i - em[2].to_i).abs
      return true if delta <= 1

      fosterish = [actual_code, expected_code].any? do |code|
        c = canonicalize_error_code(code)
        c.include?("foster-parenting") || c.include?("table-voodoo")
      end
      fosterish && delta <= 20
    end
    private_class_method :error_locations_equivalent?

    # Serialize a parse-error list for tree `#errors`, applying pair-aware script EOF aliases.
    def format_tree_errors(errors)
      errors = Array(errors)
      out = []
      i = 0
      while i < errors.length
        err = errors[i]
        nxt = errors[i + 1]

        if script_eof_pair?(err, nxt)
          first, second = script_eof_pair_names(err)
          out << format_error(err, first)
          out << format_error(nxt, second)
          i += 2
          next
        end

        code = case err.code
        when "eof-in-text"
          "expected-named-closing-tag-but-got-eof"
        when "eof-in-script-html-comment-like-text"
          script_eof_solo_name(err)
        when "eof-in-tag"
          eof_in_tag_tree_name(err)
        when "missing-semicolon-after-character-reference"
          missing_semicolon_tree_name(err)
        else
          alias_code(err.code)
        end
        out << format_error(err, code)
        i += 1
      end
      out
    end

    def script_eof_pair?(err, nxt)
      nxt &&
        err.code == "eof-in-script-html-comment-like-text" &&
        nxt.code == "eof-in-text"
    end
    private_class_method :script_eof_pair?

    # Majority mapping from tokenizer state → html5lib fixture pair.
    def script_eof_pair_names(err)
      state = err.tokenizer_state
      if DOUBLE_ESCAPED_SCRIPT_STATES.include?(state)
        ["eof-in-script-in-script", "expected-named-closing-tag-but-got-eof"]
      else
        # script_data_escaped* — majority fixtures want named-closing then text-mode EOF.
        ["expected-named-closing-tag-but-got-eof", "unexpected-eof-in-text-mode"]
      end
    end
    private_class_method :script_eof_pair_names

    def script_eof_solo_name(err)
      state = err.tokenizer_state
      if DOUBLE_ESCAPED_SCRIPT_STATES.include?(state)
        "eof-in-script-in-script"
      else
        "expected-script-data-but-got-eof"
      end
    end
    private_class_method :script_eof_solo_name

    def eof_in_tag_tree_name(err)
      case err.tokenizer_state
      when :tag_name, :end_tag_open
        "eof-in-tag-name"
      when :self_closing_start_tag
        "unexpected-EOF-after-solidus-in-tag"
      when :attribute_value_double_quoted
        "eof-in-attribute-value-double-quote"
      when :attribute_value_single_quoted
        "eof-in-attribute-value-single-quote"
      when :attribute_value_unquoted
        "eof-in-attribute-value-unquoted"
      when :attribute_name
        "eof-in-attribute-name"
      else
        # before/after attribute name — majority fixtures.
        "expected-attribute-name-but-got-eof"
      end
    end
    private_class_method :eof_in_tag_tree_name

    def missing_semicolon_tree_name(err)
      if NUMERIC_MISSING_SEMICOLON_STATES.include?(err.tokenizer_state)
        "numeric-entity-without-semicolon"
      else
        "named-entity-without-semicolon"
      end
    end
    private_class_method :missing_semicolon_tree_name

    def format_error(err, code)
      if err.line && err.column
        "(#{err.line},#{err.column}): #{code}"
      else
        code
      end
    end
    private_class_method :format_error
  end
end
