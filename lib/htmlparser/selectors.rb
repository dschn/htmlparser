# frozen_string_literal: true

module HTMLParser
  # Raised when a selector string is not supported / not parseable.
  class SelectorError < StandardError; end

  # Selectors Level 4 — readable subset for DOM `querySelector`.
  # https://www.w3.org/TR/selectors-4/
  # https://dom.spec.whatwg.org/#dom-parentnode-queryselector
  #
  # Supported: type, universal, #id, .class, attribute operators
  # (`=` `~=` `|=` `^=` `$=` `*=`, optional `i`/`s` flag), `:not` / `:is` /
  # `:where` / `:has` (relative selectors), `:nth-child` / `:nth-last-child` /
  # `:nth-of-type` / `:nth-last-of-type`, structural + form pseudos
  # (`:checked` / `:disabled` / `:enabled`), combinators, and comma lists.
  module Selectors
    Compound = Data.define(:type, :simples)
    Simple = Data.define(:kind, :args)
    Complex = Data.define(:compounds, :combinators)
    Relative = Data.define(:leading, :complex)
    # leading: :descendant | :child | :next_sibling | :subsequent_sibling

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

      compound.simples.all? { |simple| match_simple?(element, simple) }
    end

    def match_simple?(element, simple)
      args = simple.args
      case simple.kind
      when :id
        element.id == args[:name]
      when :class
        element.class_list.include?(args[:name])
      when :attr
        match_attr?(element, args[:name], args[:op], args[:value], args[:insensitive])
      when :not
        !match_any?(element, args[:list])
      when :is, :where
        match_any?(element, args[:list])
      when :has
        args[:list].any? { |rel| match_relative?(element, rel) }
      when :nth_child
        nth_match?(element_index(element), args[:a], args[:b])
      when :nth_last_child
        nth_match?(element_last_index(element), args[:a], args[:b])
      when :nth_of_type
        nth_match?(element_type_index(element), args[:a], args[:b])
      when :nth_last_of_type
        nth_match?(element_type_last_index(element), args[:a], args[:b])
      when :first_child
        element_index(element) == 1
      when :last_child
        element_index(element) == element_siblings(element).size
      when :first_of_type
        element_type_index(element) == 1
      when :last_of_type
        element_type_index(element) == element_type_siblings(element).size
      when :only_child
        element_siblings(element).size == 1
      when :only_of_type
        element_type_siblings(element).size == 1
      when :empty
        element.children.none? { |c| c.is_a?(Element) || (c.is_a?(TextNode) && !c.data.empty?) }
      when :root
        element.parent.is_a?(Document)
      when :checked
        checked?(element)
      when :disabled
        element.has_attribute?("disabled")
      when :enabled
        form_associated?(element) && !element.has_attribute?("disabled")
      else
        false
      end
    end

    def match_relative?(element, relative_sel)
      relative_candidates(element, relative_sel.leading).any? do |candidate|
        match_complex?(candidate, relative_sel.complex)
      end
    end

    def relative_candidates(element, leading)
      case leading
      when :descendant
        element.each_element_descendant.to_a
      when :child
        element.children.grep(Element)
      when :next_sibling
        sib = next_element_sibling(element)
        sib ? [sib] : []
      when :subsequent_sibling
        following_element_siblings(element)
      else
        []
      end
    end

    def match_attr?(element, name, op, value, insensitive)
      return false unless element.has_attribute?(name)

      actual = element[name].to_s
      if insensitive
        actual = actual.downcase
        value = value&.downcase
      end

      case op
      when :present then true
      when :exact then actual == value
      when :prefix then !value.empty? && actual.start_with?(value)
      when :suffix then !value.empty? && actual.end_with?(value)
      when :substring then !value.empty? && actual.include?(value)
      when :includes
        !value.empty? && !value.match?(/\s/) && actual.split(/\s+/).include?(value)
      when :dash
        actual == value || actual.start_with?("#{value}-")
      else
        false
      end
    end

    def nth_match?(index, a, b)
      if a == 0
        index == b
      elsif a.positive?
        index >= b && (index - b) % a == 0
      else
        index <= b && (b - index) % (-a) == 0
      end
    end

    def element_siblings(element)
      parent = element.parent
      return [element] unless parent

      parent.children.grep(Element)
    end

    def element_index(element)
      element_siblings(element).index(element)&.+(1) || 1
    end

    def element_last_index(element)
      sibs = element_siblings(element)
      sibs.size - (sibs.index(element) || 0)
    end

    def element_type_siblings(element)
      element_siblings(element).select { |el| el.name.casecmp?(element.name) }
    end

    def element_type_index(element)
      element_type_siblings(element).index(element)&.+(1) || 1
    end

    def element_type_last_index(element)
      sibs = element_type_siblings(element)
      sibs.size - (sibs.index(element) || 0)
    end

    def checked?(element)
      return false unless element.is_a?(Element) && element.html?

      case element.name
      when "option"
        element.selectedness || element.has_attribute?("selected")
      when "input"
        type = (element["type"] || "").downcase
        %w[checkbox radio].include?(type) && element.has_attribute?("checked")
      else
        false
      end
    end

    def form_associated?(element)
      return false unless element.is_a?(Element) && element.html?

      %w[button input select textarea optgroup option fieldset].include?(element.name)
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

    def next_element_sibling(node)
      sib = node.next_sibling
      while sib
        return sib if sib.is_a?(Element)

        sib = sib.next_sibling
      end
      nil
    end

    def following_element_siblings(node)
      out = []
      sib = next_element_sibling(node)
      while sib
        out << sib
        sib = next_element_sibling(sib)
      end
      out
    end

    # --- parser ---

    class Parser
      IDENT_AT = /\G(?:[A-Za-z_][A-Za-z0-9_-]*|-[A-Za-z_][A-Za-z0-9_-]*)/
      NTH_AT = /\G(?:even|odd|[+-]?\d*n(?:\s*[+-]\s*\d+)?|[+-]?\d+)/i

      def initialize(input)
        @input = input
        @i = 0
      end

      def parse
        skip_ws
        raise SelectorError, "empty selector" if eos?

        list = parse_complex_list
        skip_ws
        raise SelectorError, "unexpected input in selector" unless eos?

        list
      end

      def parse_complex_list
        list = [parse_complex]
        loop do
          skip_ws
          break unless consume_if(",")

          skip_ws
          raise SelectorError, "trailing comma in selector" if eos? || peek(")")

          list << parse_complex
        end
        list
      end

      def parse_relative_complex_list
        list = [parse_relative_complex]
        loop do
          skip_ws
          break unless consume_if(",")

          skip_ws
          raise SelectorError, "trailing comma in selector" if eos? || peek(")")

          list << parse_relative_complex
        end
        list
      end

      private

      def parse_relative_complex
        skip_ws
        leading = if peek(">")
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
        else
          :descendant
        end
        Relative.new(leading: leading, complex: parse_complex)
      end

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

      def parse_combinator
        saw_ws = skip_ws
        return nil if eos? || peek(",") || peek(")")

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
        elsif !peek("#") && !peek(".") && !peek("[") && !peek(":") && (ident = try_ident)
          type = ident
        end

        loop do
          if peek("#")
            @i += 1
            simples << Simple.new(kind: :id, args: {name: read_ident!("id")})
          elsif peek(".")
            @i += 1
            simples << Simple.new(kind: :class, args: {name: read_ident!("class")})
          elsif peek("[")
            simples << parse_attribute
          elsif peek(":")
            simples << parse_pseudo
          else
            break
          end
        end

        if type.nil? && simples.empty? && !saw_universal
          raise SelectorError, "expected type, universal, id, class, attribute, or pseudo-class"
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
          return Simple.new(kind: :attr, args: {name: name, op: :present, value: nil, insensitive: false})
        end

        op = if consume_if("~=")
          :includes
        elsif consume_if("|=")
          :dash
        elsif consume_if("^=")
          :prefix
        elsif consume_if("$=")
          :suffix
        elsif consume_if("*=")
          :substring
        elsif consume_if("=")
          :exact
        else
          raise SelectorError, "expected attribute operator"
        end

        skip_ws
        value = read_attr_value!
        skip_ws
        insensitive = false
        if (flag = try_ident)
          case flag.downcase
          when "i" then insensitive = true
          when "s" then insensitive = false
          else
            raise SelectorError, "expected attribute modifier i or s"
          end
          skip_ws
        end
        expect!("]")
        Simple.new(kind: :attr, args: {name: name, op: op, value: value, insensitive: insensitive})
      end

      def parse_pseudo
        expect!(":")
        name = read_ident!("pseudo-class").downcase
        case name
        when "not", "is", "where"
          expect!("(")
          list = parse_complex_list
          skip_ws
          expect!(")")
          Simple.new(kind: name.to_sym, args: {list: list})
        when "has"
          expect!("(")
          list = parse_relative_complex_list
          skip_ws
          expect!(")")
          Simple.new(kind: :has, args: {list: list})
        when "nth-child", "nth-last-child", "nth-of-type", "nth-last-of-type"
          expect!("(")
          skip_ws
          a, b = parse_nth_args
          skip_ws
          expect!(")")
          kind = name.tr("-", "_").to_sym
          Simple.new(kind: kind, args: {a: a, b: b})
        when "first-child"
          Simple.new(kind: :first_child, args: {})
        when "last-child"
          Simple.new(kind: :last_child, args: {})
        when "first-of-type"
          Simple.new(kind: :first_of_type, args: {})
        when "last-of-type"
          Simple.new(kind: :last_of_type, args: {})
        when "only-child"
          Simple.new(kind: :only_child, args: {})
        when "only-of-type"
          Simple.new(kind: :only_of_type, args: {})
        when "empty"
          Simple.new(kind: :empty, args: {})
        when "root"
          Simple.new(kind: :root, args: {})
        when "checked"
          Simple.new(kind: :checked, args: {})
        when "disabled"
          Simple.new(kind: :disabled, args: {})
        when "enabled"
          Simple.new(kind: :enabled, args: {})
        else
          raise SelectorError, "unsupported pseudo-class :#{name}"
        end
      end

      # Parse An+B / odd / even (Selectors § / CSS Syntax An+B).
      def parse_nth_args
        m = @input.match(NTH_AT, @i)
        raise SelectorError, "expected An+B, odd, or even" unless m

        token = m[0].delete(" \t\n\f\r")
        @i += m[0].length

        case token.downcase
        when "odd" then [2, 1]
        when "even" then [2, 0]
        else
          parse_an_plus_b(token)
        end
      end

      def parse_an_plus_b(token)
        if (m = token.match(/\A([+-]?\d+)\z/))
          return [0, m[1].to_i]
        end

        m = token.match(/\A([+-]?)(\d*)n(?:([+-])(\d+))?\z/i)
        raise SelectorError, "invalid An+B '#{token}'" unless m

        sign, digits, bsign, bdigits = m[1], m[2], m[3], m[4]
        a = if digits.empty?
          (sign == "-") ? -1 : 1
        else
          "#{sign}#{digits}".to_i
        end
        b = if bdigits
          "#{bsign}#{bdigits}".to_i
        else
          0
        end
        [a, b]
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
