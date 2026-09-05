# frozen_string_literal: true

require_relative "tree_construction/document"
require_relative "tree_construction/open_elements"
require_relative "tree_construction/helpers"
require_relative "tree_construction/quirks"
require_relative "tree_construction/selected_content"
require_relative "tree_construction/active_formatting"
require_relative "tree_construction/foreign_content"
require_relative "tree_construction/insertion_modes"
require_relative "tree_construction/table_modes"

module HTMLParser
  SVG_NAMESPACE = "http://www.w3.org/2000/svg"
  MATHML_NAMESPACE = "http://www.w3.org/1998/Math/MathML"

  # §13.2.6 Tree construction
  # https://html.spec.whatwg.org/multipage/parsing.html#tree-construction
  #
  # Insertion modes dispatch here. The tree builder owns tokenizer state switches
  # (RCDATA / RAWTEXT / script data / PLAINTEXT) via Tokenizer#switch_to.
  class TreeConstruction
    include Helpers
    include Quirks
    include SelectedContent
    include ActiveFormatting
    include ForeignContent
    include InsertionModes
    include TableModes

    attr_reader :tokenizer, :stack_of_open_elements, :document, :context_element

    def initialize(tokenizer:, context_element: nil, character_encoding: nil, encoding_confidence: nil)
      @tokenizer = tokenizer
      @stack_of_open_elements = OpenElements.new
      @stack_of_open_elements.on_pop = method(:option_popped_from_stack)
      @document = Document.new
      @document.character_encoding = character_encoding
      @document.encoding_confidence = encoding_confidence
      @context_element = context_element
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
      # §13.2.5.42 — CDATA only when adjusted current node is non-HTML.
      @tokenizer.adjusted_current_node_provider = method(:adjusted_current_node)
    end

    def fragment?
      !@context_element.nil?
    end

    def call(&block)
      block ||= ->(_token) {}
      setup_fragment_parsing if fragment?

      tokenizer.parse do |token|
        process(token)
        block.call(token)
        break if @halt
      end

      result = fragment? ? extract_fragment : document
      result.parse_errors = tokenizer.parse_errors
      result
    end

    private

    # §13.4 Parsing HTML fragments — parser setup (html root + insertion mode).
    def setup_fragment_parsing
      root = Element.new("html")
      document.append_child(root)
      stack_of_open_elements.push(root)

      if @context_element.html? && @context_element.name == "template"
        @template_insertion_modes << :in_template
      end

      if @context_element.html? && @context_element.name == "form"
        @form_element = @context_element
      end

      reset_insertion_mode_appropriately
    end

    def extract_fragment
      fragment = DocumentFragment.new
      root = document.children.find { |c| c.is_a?(Element) && c.html? && c.name == "html" }
      return fragment unless root

      root.children.dup.each { |child| fragment.append_child(child) }
      fragment
    end

    def process(token)
      @current_token = token
      guard = 0
      loop do
        @reprocess = false
        if foreign_content?(token)
          process_foreign_content(token)
        else
          method = :"process_#{@insertion_mode}"
          if respond_to?(method, true)
            send(method, token)
          else
            # Unknown insertion mode name — should not happen once modes are wired.
            @insertion_mode = :in_body
            @reprocess = true
          end
        end
        guard += 1
        raise "insertion-mode reprocess loop (#{@insertion_mode})" if guard > 64
        break unless @reprocess
      end

      # §13.2.6 — trailing solidus on a non-void HTML start tag (flag never acknowledged).
      if token.is_a?(StartTagToken) && token.self_closing && !token.self_closing_acknowledged
        parse_error("non-void-html-element-start-tag-with-trailing-solidus", token)
      end
    end
  end
end
