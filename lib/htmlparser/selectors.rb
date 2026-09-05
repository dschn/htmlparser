# frozen_string_literal: true

module HTMLParser
  # Raised when a selector string is not supported / not parseable.
  class SelectorError < StandardError; end

  # Selectors Level 4 — small readable subset for DOM `querySelector`.
  # https://www.w3.org/TR/selectors-4/
  # https://dom.spec.whatwg.org/#dom-parentnode-queryselector
  #
  # Supported: type, universal, #id, .class, [attr] / [attr=value],
  # combinators (descendant / > / + / ~), and comma-separated lists.
  module Selectors
    Compound = Data.define(:type, :simples)
    # type: String or nil (nil = universal / omitted type)
    Simple = Data.define(:kind, :name, :value)
    # kind: :id | :class | :attr_present | :attr_exact
    Complex = Data.define(:compounds, :combinators)
    # compounds.length == combinators.length + 1
    # combinators: :descendant | :child | :next_sibling | :subsequent_sibling

    module_function

    def parse(selector)
      Parser.new(selector.to_s).parse
    end

    def query_selector(root, selector)
      list = parse(selector)
      root.each_element_descendant.find { |el| match_any?(el, list) }
    end

    def query_selector_all(root, selector)
      list = parse(selector)
      root.each_element_descendant.select { |el| match_any?(el, list) }
    end

    def matches?(element, selector)
      match_any?(element, parse(selector))
    end

    def match_any?(element, complex_list)
      complex_list.any? { |complex| match_complex?(element, complex) }
    end

    def match_complex?(element, complex)
      compounds = complex.compounds
      combinators = complex.combinators
      return false unless match_compound?(element, compounds.last)

      current = element
      (compounds.length - 2).downto(0) do |i|
        current = relative(current, combinators[i], compounds[i])
        return false unless current
      end
      true
    end

    def match_compound?(element, compound)
      if compound.type
        return false unless element.name.casecmp?(compound.type)
      end

      compound.simples.all? do |simple|
        case simple.kind
        when :id
          element.id == simple.name
        when :class
          element.class_list.include?(simple.name)
        when :attr_present
          element.has_attribute?(simple.name)
        when :attr_exact
          element[simple.name] == simple.value
        else
          false
        end
      end
    end

    def relative(from, combinator, compound)
      case combinator
      when :descendant
        node = from.parent
        while node
          return node if node.is_a?(Element) && match_compound?(node, compound)

          node = node.parent
        end
        nil
      when :child
        parent = from.parent
        parent if parent.is_a?(Element) && match_compound?(parent, compound)
      when :next_sibling
        sib = previous_element_sibling(from)
        sib if sib && match_compound?(sib, compound)
      when :subsequent_sibling
        sib = previous_element_sibling(from)
        while sib
          return sib if match_compound?(sib, compound)

          sib = previous_element_sibling(sib)
        end
        nil
      end
    end

    def previous_element_sibling(node)
      sib = node.previous_sibling
      while sib
        return sib if sib.is_a?(Element)

        sib = sib.previous_sibling
      end
      nil
    end

    # --- parser ---

    class Parser
      # CSS <ident-token> without escapes — good enough for this subset.
      IDENT_AT = /\G(?:[A-Za-z_][A-Za-z0-9_-]*|-[A-Za-z_][A-Za-z0-9_-]*)/

      def initialize(input)
        @input = input
        @i = 0
      end

      def parse
        skip_ws
        raise SelectorError, "empty selector" if eos?

        list = []
        loop do
          list << parse_complex
          skip_ws
          break if eos?
          raise SelectorError, "expected ',' or end of selector" unless consume_if(",")

          skip_ws
          raise SelectorError, "trailing comma in selector" if eos?
        end
        list
      end

      private

      def parse_complex
        compounds = [parse_compound]
        combinators = []
        loop do
          comb = parse_combinator
          break unless comb

          compounds << parse_compound
          combinators << comb
        end
        Complex.new(compounds: compounds, combinators: combinators)
      end

      # Returns a combinator symbol, or nil if the next token starts a compound / end / comma.
      def parse_combinator
        saw_ws = skip_ws
        return nil if eos? || peek(",")

        if peek(">")
          @i += 1
          skip_ws
          :child
        elsif peek("+")
          @i += 1
          skip_ws
          :next_sibling
        elsif peek("~")
          @i += 1
          skip_ws
          :subsequent_sibling
        elsif saw_ws
          :descendant
        end
      end

      def parse_compound
        skip_ws
        saw_universal = false
        type = nil
        simples = []

        if peek("*")
          @i += 1
          saw_universal = true
        elsif (ident = try_ident)
          type = ident
        end

        loop do
          if peek("#")
            @i += 1
            name = read_ident!("id")
            simples << Simple.new(kind: :id, name: name, value: nil)
          elsif peek(".")
            @i += 1
            name = read_ident!("class")
            simples << Simple.new(kind: :class, name: name, value: nil)
          elsif peek("[")
            simples << parse_attribute
          else
            break
          end
        end

        if type.nil? && simples.empty? && !saw_universal
          raise SelectorError, "expected type, universal, id, class, or attribute selector"
        end

        Compound.new(type: type, simples: simples)
      end

      def parse_attribute
        expect!("[")
        skip_ws
        name = read_ident!("attribute name")
        skip_ws
        if peek("]")
          @i += 1
          return Simple.new(kind: :attr_present, name: name, value: nil)
        end

        expect!("=")
        skip_ws
        value = read_attr_value!
        skip_ws
        expect!("]")
        Simple.new(kind: :attr_exact, name: name, value: value)
      end

      def read_attr_value!
        if peek("'") || peek('"')
          quote = @input[@i]
          @i += 1
          start = @i
          while !eos? && @input[@i] != quote
            @i += 1
          end
          raise SelectorError, "unclosed attribute value" if eos?

          value = @input[start...@i]
          @i += 1
          value
        else
          read_ident!("attribute value")
        end
      end

      def try_ident
        m = @input.match(IDENT_AT, @i)
        return nil unless m

        @i += m[0].length
        m[0]
      end

      def read_ident!(what)
        ident = try_ident
        raise SelectorError, "expected #{what}" unless ident

        ident
      end

      def skip_ws
        start = @i
        @i += 1 while !eos? && @input[@i].match?(/\s/)
        @i > start
      end

      def peek(str)
        @input[@i, str.length] == str
      end

      def consume_if(str)
        return false unless peek(str)

        @i += str.length
        true
      end

      def expect!(str)
        raise SelectorError, "expected #{str.inspect}" unless consume_if(str)
      end

      def eos?
        @i >= @input.length
      end
    end
    private_constant :Parser
  end
end
