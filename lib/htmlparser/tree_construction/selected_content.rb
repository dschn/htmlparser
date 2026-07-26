# frozen_string_literal: true

module HTMLParser
  class TreeConstruction
    # §4.10.7 / §4.10.10 / §4.10.17 — select selectedness + selectedcontent reflection.
    module SelectedContent
      private

      # §4.10.10 — when an option is popped off the stack of open elements.
      def option_popped_from_stack(element)
        return unless element.is_a?(Element) && element.html? && element.name == "option"

        maybe_clone_option_into_selectedcontent(element)
      end

      # §4.10.10 — maybe clone an option into selectedcontent.
      def maybe_clone_option_into_selectedcontent(option)
        select = nearest_ancestor_select(option)
        return if select.nil?
        return unless option.selectedness

        selectedcontent = enabled_selectedcontent(select)
        return if selectedcontent.nil?

        clone_option_into_selectedcontent(option, selectedcontent)
      end

      # §4.10.10 — clone an option into a selectedcontent.
      def clone_option_into_selectedcontent(option, selectedcontent)
        selectedcontent.children.dup.each { |child| selectedcontent.remove_child(child) }
        option.children.each do |child|
          selectedcontent.append_child(clone_node_subtree(child))
        end
      end

      # §4.10.7 — get a select's enabled selectedcontent.
      def enabled_selectedcontent(select)
        return nil if select.attributes.key?("multiple")

        selectedcontent = first_descendant(select) { |el| el.html? && el.name == "selectedcontent" }
        return nil if selectedcontent.nil? || selectedcontent.disabled

        selectedcontent
      end

      # §4.10.7 — selectedness setting algorithm.
      def run_selectedness_setting(select)
        return if select.nil?

        options = list_of_options(select)
        if !select.attributes.key?("multiple") && display_size(select) == 1 && options.none?(&:selectedness)
          first = options.find { |opt| !option_disabled?(opt) }
          first.selectedness = true if first
          return
        end

        if !select.attributes.key?("multiple")
          selected = options.select(&:selectedness)
          selected[0...-1].each { |opt| opt.selectedness = false } if selected.size >= 2
        end
      end

      # §4.10.7 — display size of a select element.
      def display_size(select)
        raw = select.attributes["size"]
        if raw
          # Non-negative integer parsing (common microsyntaxes): ASCII digits only.
          return raw.to_i if raw.match?(/\A[0-9]+\z/)
        end
        select.attributes.key?("multiple") ? 4 : 1
      end

      # §4.10.7 — list of options for a select element.
      def list_of_options(select)
        options = []
        node = first_descendant_node(select)
        while node
          if html_named?(node, "option")
            options << node
          end

          skip_descendants = html_named?(node, "select") ||
            html_named?(node, "hr") ||
            html_named?(node, "option") ||
            html_named?(node, "datalist") ||
            (html_named?(node, "optgroup") && ancestor_optgroup_between?(node, select))

          node = if skip_descendants
            next_descendant_excluding(select, node)
          else
            next_descendant(select, node)
          end
        end
        options
      end

      def nearest_ancestor_select(element)
        node = element.parent
        while node
          return node if node.is_a?(Element) && node.html? && node.name == "select"
          node = node.parent
        end
        nil
      end

      def option_disabled?(option)
        return true if option.attributes.key?("disabled")

        node = option.parent
        while node
          break if node.is_a?(Element) && node.html? && node.name == "select"
          return true if node.is_a?(Element) && node.html? && node.name == "optgroup" && node.attributes.key?("disabled")
          node = node.parent
        end
        false
      end

      def clone_node_subtree(node)
        case node
        when Element
          clone = Element.new(node.name, attributes: node.attributes.dup, namespace: node.namespace)
          clone.selectedness = node.selectedness
          clone.disabled = node.disabled
          node.children.each { |child| clone.append_child(clone_node_subtree(child)) }
          clone
        when TextNode
          TextNode.new(+node.data.dup)
        when Comment
          Comment.new(node.data)
        else
          raise "unsupported clone: #{node.class}"
        end
      end

      def html_named?(node, name)
        node.is_a?(Element) && node.html? && node.name == name
      end

      def first_descendant(root)
        stack = root.children.reverse
        until stack.empty?
          node = stack.pop
          return node if node.is_a?(Element) && yield(node)
          stack.concat(node.children.reverse) if node.is_a?(Node)
        end
        nil
      end

      def first_descendant_node(root)
        root.children.first
      end

      def next_descendant(root, node)
        return node.children.first unless node.children.empty?

        next_descendant_excluding(root, node)
      end

      def next_descendant_excluding(root, node)
        current = node
        while current && !current.equal?(root)
          parent = current.parent
          break unless parent

          idx = parent.children.index(current)
          return parent.children[idx + 1] if idx && idx + 1 < parent.children.size

          current = parent
        end
        nil
      end

      def ancestor_optgroup_between?(optgroup, select)
        node = optgroup.parent
        while node && !node.equal?(select)
          return true if html_named?(node, "optgroup")
          node = node.parent
        end
        false
      end
    end
  end
end
