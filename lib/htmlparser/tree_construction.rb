# frozen_string_literal: true

module HTMLParser
  class Document
  end

  # 13.2.6 Tree construction
  class TreeConstruction
    def initialize(tokenizer:)
      @tokenizer = tokenizer
      @stack_of_open_elements = []
      @document = Document.new
    end

    def call(&block)
      block ||= ->(token) { puts token.inspect }
      tokenizer.parse do |next_token|
        block.call(next_token)
      end
    end

    private

    attr_reader :tokenizer
  end
end
