# frozen_string_literal: true

module HTMLParser
  # Raised when a selector string is not supported / not parseable.
  class SelectorError < StandardError; end

  # Selectors Level 4 — readable subset for DOM `querySelector`.
  # https://www.w3.org/TR/selectors-4/
  # https://dom.spec.whatwg.org/#dom-parentnode-queryselector
  module Selectors
    Compound = Data.define(:type_ns, :type_name, :simples)
    # type_ns: nil (no type) | :default | :any | :none
    # type_name: String or nil (universal)
    Simple = Data.define(:kind, :args)
    Complex = Data.define(:compounds, :combinators)
    Relative = Data.define(:leading, :complex)

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
      return false unless match_type?(element, compound.type_ns, compound.type_name)

      compound.simples.all? { |simple| match_simple?(element, simple) }
    end

    def match_type?(element, type_ns, type_name)
      return true if type_ns.nil?

      if type_name && !element.name.casecmp?(type_name)
        return false
      end

      case type_ns
      when :any, :default
        true
      when :none
        element.namespace.nil? || element.namespace == ""
      else
        false
      end
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
      when :lang
        lang_matches?(element, args[:lang])
      when :link, :visited
        link_like?(element)
      when :target
        target?(element)
      when :never
        false
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
      when :descendant then element.each_element_descendant.to_a
      when :child then element.children.grep(Element)
      when :next_sibling
        sib = next_element_sibling(element)
        sib ? [sib] : []
      when :subsequent_sibling then following_element_siblings(element)
      else []
      end
    end

    def match_attr?(element, name, op, value, insensitive)
      key = html_attr_key(element, name)
      return false unless key

      actual = element.attributes[key].to_s
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

    # HTML attribute names are ASCII-case-insensitive; foreign attrs keep exact keys.
    def html_attr_key(element, name)
      if element.html?
        lower = name.downcase
        return lower if element.attributes.key?(lower)

        element.attributes.keys.find { |k| k.downcase == lower }
      else
        return name if element.attributes.key?(name)

        element.attributes.keys.find { |k| k.casecmp?(name) }
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

    def link_like?(element)
      return false unless element.is_a?(Element) && element.html?
      return false unless %w[a area].include?(element.name)

      element.has_attribute?("href")
    end

    def target?(element)
      return false unless element.is_a?(Element)

      tid = target_id_for(element)
      !tid.nil? && !tid.empty? && element.id == tid
    end

    def target_id_for(element)
      node = element
      while node
        return node.css_target_id if node.is_a?(Document) && node.respond_to?(:css_target_id)

        node = node.parent
      end
      "target"
    end

    def lang_matches?(element, lang)
      want = lang.downcase
      node = element
      while node
        if node.is_a?(Element) && node.has_attribute?("lang")
          have = node["lang"].to_s.downcase
          return have == want || have.start_with?("#{want}-")
        end
        node = node.parent
      end
      false
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
      NTH_AT = /\G(?:even|odd|[+-]?\d*n(?:\s*[+-]\s*\d+)?|[+-]?\d+)/i
      HEX = /[0-9a-fA-F]/

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
        type_ns = nil
        type_name = nil
        simples = []
        saw_type = false

        if !peek("#") && !peek(".") && !peek("[") && !peek(":")
          t = try_type_selector
          if t
            type_ns, type_name = t
            saw_type = true
          end
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

        if !saw_type && simples.empty?
          raise SelectorError, "expected type, universal, id, class, attribute, or pseudo-class"
        end

        Compound.new(type_ns: type_ns, type_name: type_name, simples: simples)
      end

      # Returns [type_ns, type_name] or nil.
      def try_type_selector
        if peek("|")
          @i += 1
          return [:none, nil] if consume_if("*")

          name = try_ident
          raise SelectorError, "expected type name after |" unless name

          return [:none, name]
        end

        if peek("*")
          @i += 1
          if peek("|")
            @i += 1
            return [:any, nil] if consume_if("*")

            name = try_ident
            raise SelectorError, "expected type name after *|" unless name

            return [:any, name]
          end
          return [:default, nil]
        end

        name = try_ident
        return nil unless name

        if peek("|")
          raise SelectorError, "undeclared namespace prefix #{name}"
        end

        [:default, name]
      end

      def parse_attribute
        expect!("[")
        skip_ws
        name = read_attr_name!
        skip_ws
        if peek("]") || eos?
          @i += 1 if peek("]")
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
        @i += 1 if peek("]") # optional closing ] (WPT recovery cases)
        Simple.new(kind: :attr, args: {name: name, op: op, value: value, insensitive: insensitive})
      end

      def read_attr_name!
        if peek("*") && @input[@i + 1] == "|"
          @i += 2
          return read_ident!("attribute name")
        end
        if peek("|") && @input[@i + 1] != "="
          @i += 1
          return read_ident!("attribute name")
        end
        name = try_ident
        raise SelectorError, "expected attribute name" unless name
        if peek("|") && @input[@i + 1] != "="
          raise SelectorError, "undeclared namespace prefix #{name}"
        end
        name
      end

      def parse_pseudo
        expect!(":")
        element = false
        if peek(":")
          @i += 1
          element = true
        end
        name = read_ident!("pseudo-class").downcase

        if element
          unless %w[first-line first-letter before after slotted].include?(name)
            raise SelectorError, "unknown pseudo-element ::#{name}"
          end
          parse_pseudo_element_args(name)
          return Simple.new(kind: :never, args: {})
        end

        if %w[first-line first-letter before after].include?(name)
          parse_pseudo_element_args(name)
          return Simple.new(kind: :never, args: {})
        end

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
          Simple.new(kind: name.tr("-", "_").to_sym, args: {a: a, b: b})
        when "lang"
          expect!("(")
          skip_ws
          lang = read_ident!("language")
          skip_ws
          expect!(")")
          Simple.new(kind: :lang, args: {lang: lang})
        when "first-child" then Simple.new(kind: :first_child, args: {})
        when "last-child" then Simple.new(kind: :last_child, args: {})
        when "first-of-type" then Simple.new(kind: :first_of_type, args: {})
        when "last-of-type" then Simple.new(kind: :last_of_type, args: {})
        when "only-child" then Simple.new(kind: :only_child, args: {})
        when "only-of-type" then Simple.new(kind: :only_of_type, args: {})
        when "empty" then Simple.new(kind: :empty, args: {})
        when "root" then Simple.new(kind: :root, args: {})
        when "checked" then Simple.new(kind: :checked, args: {})
        when "disabled" then Simple.new(kind: :disabled, args: {})
        when "enabled" then Simple.new(kind: :enabled, args: {})
        when "link" then Simple.new(kind: :link, args: {})
        when "visited" then Simple.new(kind: :visited, args: {})
        when "target" then Simple.new(kind: :target, args: {})
        else
          raise SelectorError, "unsupported pseudo-class :#{name}"
        end
      end

      def parse_pseudo_element_args(name)
        return unless peek("(")

        @i += 1
        depth = 1
        while !eos? && depth.positive?
          ch = @input[@i]
          @i += 1
          depth += 1 if ch == "("
          depth -= 1 if ch == ")"
        end
        # Unclosed args (e.g. ::slotted(foo) are tolerated — selector matches nothing.
        nil
      end

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
        b = bdigits ? "#{bsign}#{bdigits}".to_i : 0
        [a, b]
      end

      def read_attr_value!
        if peek("'") || peek('"')
          quote = @input[@i]
          @i += 1
          value = +""
          while !eos? && @input[@i] != quote
            value << if @input[@i] == "\\"
              read_escape!
            else
              ch = @input[@i]
              @i += 1
              ch
            end
          end
          @i += 1 if peek(quote) # optional close quote
          value
        else
          read_ident!("attribute value")
        end
      end

      def try_ident
        return nil if eos?
        return nil unless can_start_ident?

        buf = +""
        if peek("-")
          buf << "-"
          @i += 1
        end

        if peek("\\")
          buf << read_escape!
        elsif !eos? && name_start_char?(@input[@i])
          buf << @input[@i]
          @i += 1
        else
          @i -= buf.length
          return nil
        end

        until eos?
          if @input[@i] == "\\"
            buf << read_escape!
          elsif ident_continue?(@input[@i])
            buf << @input[@i]
            @i += 1
          else
            break
          end
        end
        buf
      end

      def can_start_ident?
        return false if eos?

        ch = @input[@i]
        return true if name_start_char?(ch) || ch == "\\"
        return false unless ch == "-"
        return false if @i + 1 >= @input.length

        nxt = @input[@i + 1]
        name_start_char?(nxt) || nxt == "\\"
      end

      def name_start_char?(ch)
        ch == "_" || ch.match?(/[A-Za-z]/) || ch.ord > 0x7F
      end

      def ident_continue?(ch)
        ch == "_" || ch == "-" || ch.match?(/[A-Za-z0-9]/) || ch.ord > 0x7F
      end

      def read_ident!(what)
        ident = try_ident
        raise SelectorError, "expected #{what}" unless ident && !ident.empty?

        ident
      end

      def read_escape!
        raise SelectorError, "expected escape" unless consume_if("\\")
        raise SelectorError, "invalid escape" if eos?

        if @input[@i].match?(HEX)
          hex = +""
          6.times do
            break if eos? || !@input[@i].match?(HEX)

            hex << @input[@i]
            @i += 1
          end
          @i += 1 if !eos? && @input[@i].match?(/\s/)
          cp = hex.to_i(16)
          cp = 0xFFFD if cp.zero? || cp > 0x10FFFF || cp.between?(0xD800, 0xDFFF)
          [cp].pack("U")
        elsif @input[@i] == "\n"
          raise SelectorError, "escaped newline"
        else
          ch = @input[@i]
          @i += 1
          ch
        end
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
