# frozen_string_literal: true

require_relative "tree_construction/document"
require_relative "tree_construction/open_elements"
require_relative "tree_construction/helpers"
require_relative "tree_construction/active_formatting"
require_relative "tree_construction/insertion_modes"
require_relative "tree_construction/table_modes"

module HTMLParser
  # §13.2.6 Tree construction
  # https://html.spec.whatwg.org/multipage/parsing.html#tree-construction
  #
  # Insertion modes dispatch here. The tree builder owns tokenizer state switches
  # (RCDATA / RAWTEXT / script data / PLAINTEXT) via Tokenizer#switch_to.
  class TreeConstruction
    include Helpers
    include ActiveFormatting
    include InsertionModes
    include TableModes

    attr_reader :tokenizer, :stack_of_open_elements, :document

    def initialize(tokenizer:)
      @tokenizer = tokenizer
      @stack_of_open_elements = OpenElements.new
      @document = Document.new
      @insertion_mode = :initial
      @original_insertion_mode = nil
      @head_element = nil
      @form_element = nil
      @frameset_ok = true
      @active_formatting_elements = []
      @reprocess = false
      @halt = false
      @ignore_next_lf = false
      @foster_parenting = false
      @pending_table_character_tokens = []
      @template_insertion_modes = []
    end

    def call(&block)
      block ||= ->(_token) {}

      tokenizer.parse do |token|
        process(token)
        block.call(token)
        break if @halt
      end

      document
    end

    private

    def process(token)
      loop do
        @reprocess = false
        method = :"process_#{@insertion_mode}"
        if respond_to?(method, true)
          send(method, token)
        else
          # Unimplemented modes: degrade toward in body so the suite can progress.
          @insertion_mode = :in_body
          @reprocess = true
        end
        break unless @reprocess
      end
    end
  end
end
