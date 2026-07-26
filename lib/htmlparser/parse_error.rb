# frozen_string_literal: true

require_relative "html5lib_tree_error_names"

module HTMLParser
  class ParseError
    attr_reader :code
    attr_accessor :line, :column, :tokenizer_state

    def initialize(code, line: nil, column: nil, tokenizer_state: nil)
      @code = code.to_s
      @line = line
      @column = column
      @tokenizer_state = tokenizer_state
    end

    def ==(other)
      other.is_a?(ParseError) && other.code == code &&
        other.line == line && other.column == column
    end

    # html5lib / WPT tree-construction `#errors` line form (1:1 alias only).
    # Prefer `Html5libTreeErrorNames.format_tree_errors` for full tree lists.
    def to_html5lib(tree: false)
      name = tree ? Html5libTreeErrorNames.alias_code(code) : code
      if line && column
        "(#{line},#{column}): #{name}"
      else
        name
      end
    end
  end

  class NotImplementedError < ::NotImplementedError
    attr_reader :detail

    def initialize(detail = nil)
      @detail = detail
      message = if detail
        "HTML parser feature not implemented: #{detail}"
      else
        "HTML parser feature not implemented"
      end
      super(message)
    end
  end
end
