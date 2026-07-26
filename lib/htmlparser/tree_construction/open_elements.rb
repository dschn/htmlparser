# frozen_string_literal: true

module HTMLParser
  # Stack of open elements (§13.2.4.2).
  class OpenElements
    # Foreign namespace elements that also terminate "in scope" walks.
    MATHML_SCOPE_BARRIERS = %w[mi mo mn ms mtext annotation-xml].freeze
    SVG_SCOPE_BARRIERS = %w[foreignObject desc title].freeze

    attr_accessor :on_pop

    def initialize
      @elements = []
      @on_pop = nil
    end

    def push(element)
      @elements.push(element)
    end

    def pop
      el = @elements.pop
      @on_pop&.call(el) if el
      el
    end

    def pop_until(name)
      loop do
        el = pop
        break if el.nil? || (el.html? && el.name == name)
      end
    end

    def remove(element)
      @elements.delete(element)
    end

    def include?(element)
      @elements.include?(element)
    end

    def index(element)
      @elements.index(element)
    end

    def [](i)
      @elements[i]
    end

    def []=(i, element)
      @elements[i] = element
    end

    def insert_immediately_below(existing, new_element)
      idx = @elements.index(existing)
      return push(new_element) unless idx

      @elements.insert(idx + 1, new_element)
    end

    def current
      @elements.last
    end

    def empty?
      @elements.empty?
    end

    def include_html?(name)
      @elements.any? { |el| el.html? && el.name == name }
    end

    # Scope check by node identity (used by adoption agency).
    def element_in_scope?(element)
      html_exits = scope_exit_names(:default)
      @elements.reverse_each do |el|
        return true if el.equal?(element)
        return false if scope_barrier?(el, html_exits)
      end
      false
    end

    def first_html(name)
      @elements.find { |el| el.html? && el.name == name }
    end

    def to_a
      @elements.dup
    end

    # §13.2.4.2 — element in scope (and button / list-item variants).
    def in_scope?(target_names, list: :default)
      target_names = Array(target_names)
      html_exits = scope_exit_names(list)
      @elements.reverse_each do |el|
        return true if el.html? && target_names.include?(el.name)
        return false if scope_barrier?(el, html_exits)
      end
      false
    end

    def in_button_scope?(name)
      in_scope?(name, list: :button)
    end

    def in_list_item_scope?(name)
      in_scope?(name, list: :list_item)
    end

    # §13.2.4.2 — element in table scope.
    def in_table_scope?(target_names)
      target_names = Array(target_names)
      @elements.reverse_each do |el|
        return true if el.html? && target_names.include?(el.name)
        return false if el.html? && %w[html table template].include?(el.name)
      end
      false
    end

    private

    def scope_exit_names(list)
      # §13.2.4.2 — select is an in-scope barrier (customizable <select> / <hr> in select).
      base = %w[
        applet caption html table td th marquee object select template
      ]
      case list
      when :button
        base + %w[button]
      when :list_item
        base + %w[ol ul]
      else
        base
      end
    end

    # HTML specials plus MathML/SVG integration-point elements (§13.2.4.2).
    def scope_barrier?(el, html_exits)
      if el.html?
        html_exits.include?(el.name)
      elsif el.namespace == MATHML_NAMESPACE
        MATHML_SCOPE_BARRIERS.include?(el.name)
      elsif el.namespace == SVG_NAMESPACE
        SVG_SCOPE_BARRIERS.include?(el.name)
      else
        false
      end
    end
  end
end
