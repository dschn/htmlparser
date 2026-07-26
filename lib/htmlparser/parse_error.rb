# frozen_string_literal: true

module HTMLParser
  class ParseError
    attr_reader :code

    def initialize(code)
      @code = code.to_s
    end

    def ==(other)
      other.is_a?(ParseError) && other.code == code
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
