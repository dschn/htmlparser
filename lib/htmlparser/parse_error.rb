# frozen_string_literal: true

module HTMLParser
  class ParseError
    attr_reader :code
    attr_accessor :line, :column

    def initialize(code, line: nil, column: nil)
      @code = code.to_s
      @line = line
      @column = column
    end

    def ==(other)
      other.is_a?(ParseError) && other.code == code &&
        other.line == line && other.column == column
    end

    # html5lib / WPT tree-construction `#errors` line form.
    def to_html5lib
      if line && column
        "(#{line},#{column}): #{code}"
      else
        code
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
