# frozen_string_literal: true

module HTMLParser
  # Stack of open elements (§13.2.4.2).
  class OpenElements
    def initialize
      @elements = []
    end

    def push(element)
      @elements.push(element)
    end

    def pop
      @elements.pop
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
      @elements.reverse_each do |el|
        return true if el.equal?(element)
        return false if el.html? && scope_exit_names(:default).include?(el.name)
        return false unless el.html?
      end
      false
    end

    def first_html(name)
      @elements.find { |el| el.html? && el.name == name }
    end

    def to_a
      @elements.dup
    end

    # §13.2.4.2 — element in scope (HTML variant).
    def in_scope?(target_names, list: :default)
      target_names = Array(target_names)
      scope_exits = scope_exit_names(list)
      @elements.reverse_each do |el|
        return true if el.html? && target_names.include?(el.name)
        return false if el.html? && scope_exits.include?(el.name)
        # Non-HTML namespace elements also act as scope exits in the default list.
        return false if list == :default && !el.html?
      end
      false
    end

    def in_button_scope?(name)
      in_scope?(name, list: :button)
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
      base = %w[
        applet caption html table td th marquee object template
      ]
      case list
      when :button
        base + %w[button]
      else
        base
      end
    end
  end
end
