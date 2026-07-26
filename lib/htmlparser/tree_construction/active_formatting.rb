# frozen_string_literal: true

module HTMLParser
  class TreeConstruction
    # §13.2.4.3 list of active formatting elements + reconstruct + adoption agency.
    module ActiveFormatting
      FORMATTING_ELEMENTS = %w[
        a b big code em font i nobr s small strike strong tt u
      ].freeze

      private

      def push_onto_list_of_active_formatting_elements(element)
        # Noah's Ark: remove earliest of 3 identical elements after last marker.
        family = afe_entries_after_last_marker
        matches = family.select { |el| same_element_shape?(el, element) }
        if matches.size >= 3
          @active_formatting_elements.delete(matches.first)
        end
        @active_formatting_elements << element
      end

      def afe_entries_after_last_marker
        idx = @active_formatting_elements.rindex(:marker)
        if idx
          @active_formatting_elements[(idx + 1)..] || []
        else
          @active_formatting_elements
        end
      end

      def same_element_shape?(a, b)
        a.is_a?(Element) && b.is_a?(Element) &&
          a.name == b.name &&
          a.namespace == b.namespace &&
          a.attributes == b.attributes
      end

      def clear_active_formatting_elements_to_last_marker
        while (entry = @active_formatting_elements.pop)
          break if entry == :marker
        end
      end

      # §13.2.4.3 — reconstruct the active formatting elements
      def reconstruct_active_formatting_elements
        return if @active_formatting_elements.empty?

        last = @active_formatting_elements.last
        return if last == :marker || stack_of_open_elements.include?(last)

        entry_index = @active_formatting_elements.size - 1

        # Rewind
        loop do
          break if entry_index.zero?

          entry_index -= 1
          entry = @active_formatting_elements[entry_index]
          break if entry == :marker || stack_of_open_elements.include?(entry)
        end

        # If we stopped on a marker / in-stack entry, advance past it.
        entry = @active_formatting_elements[entry_index]
        if entry == :marker || stack_of_open_elements.include?(entry)
          entry_index += 1
        end

        # Create
        while entry_index < @active_formatting_elements.size
          entry = @active_formatting_elements[entry_index]
          token = entry.token || StartTagToken.new(entry.name)
          new_element = insert_html_element(token)
          @active_formatting_elements[entry_index] = new_element
          entry_index += 1
        end
      end

      def find_formatting_element_after_last_marker(subject)
        afe_entries_after_last_marker.reverse_each do |el|
          return el if el.is_a?(Element) && el.html? && el.name == subject
        end
        nil
      end

      # The adoption agency algorithm (in body).
      def adoption_agency_algorithm(token)
        subject = token.name

        # Step 1 — common case shortcut
        if current_node&.html? && current_node.name == subject &&
            !@active_formatting_elements.include?(current_node)
          stack_of_open_elements.pop
          return
        end

        outer_loop_counter = 0
        loop do
          return if outer_loop_counter >= 8

          outer_loop_counter += 1

          formatting_element = find_formatting_element_after_last_marker(subject)
          unless formatting_element
            any_other_end_tag(token)
            return
          end

          unless stack_of_open_elements.include?(formatting_element)
            parse_error("adoption-agency-1.1")
            @active_formatting_elements.delete(formatting_element)
            return
          end

          unless stack_of_open_elements.element_in_scope?(formatting_element)
            parse_error("adoption-agency-1.2")
            return
          end

          parse_error("adoption-agency-1.3") unless formatting_element.equal?(current_node)

          formatting_index = stack_of_open_elements.index(formatting_element)
          furthest_block = stack_of_open_elements.to_a[(formatting_index + 1)..]&.find do |node|
            node.html? && special_category?(node.name)
          end

          if furthest_block.nil?
            loop do
              el = stack_of_open_elements.pop
              break if el.nil? || el.equal?(formatting_element)
            end
            @active_formatting_elements.delete(formatting_element)
            return
          end

          common_ancestor = stack_of_open_elements[formatting_index - 1]
          bookmark = @active_formatting_elements.index(formatting_element)

          node = furthest_block
          last_node = furthest_block
          inner_loop_counter = 0
          above_cache = {} # node => element that was above it (for removed nodes)

          elements = stack_of_open_elements.to_a
          elements.each_cons(2) { |above, below| above_cache[below] = above }

          loop do
            inner_loop_counter += 1
            node = stack_of_open_elements.include?(node) ?
              stack_of_open_elements[stack_of_open_elements.index(node) - 1] :
              above_cache[node]

            break if node.nil? || node.equal?(formatting_element)

            if inner_loop_counter > 3 && @active_formatting_elements.include?(node)
              @active_formatting_elements.delete(node)
            end

            unless @active_formatting_elements.include?(node)
              # Remember what was above before removal
              idx = stack_of_open_elements.index(node)
              above_cache[node] = stack_of_open_elements[idx - 1] if idx && idx > 0
              stack_of_open_elements.remove(node)
              next
            end

            clone_token = node.token || StartTagToken.new(node.name)
            new_element = create_element_for_token(clone_token)
            afe_idx = @active_formatting_elements.index(node)
            @active_formatting_elements[afe_idx] = new_element if afe_idx
            stack_idx = stack_of_open_elements.index(node)
            if stack_idx
              above_cache[new_element] = above_cache[node] ||
                ((stack_idx > 0) ? stack_of_open_elements[stack_idx - 1] : nil)
              stack_of_open_elements[stack_idx] = new_element
            end
            node = new_element

            if last_node.equal?(furthest_block)
              bookmark = @active_formatting_elements.index(node) + 1
            end

            node.append_child(last_node)
            last_node = node
          end

          # Insert lastNode into commonAncestor at appropriate place (foster-aware).
          location = appropriate_place_for_inserting_a_node(common_ancestor)
          insert_node_at(location, last_node)

          fmt_token = formatting_element.token || StartTagToken.new(formatting_element.name)
          new_formatting = create_element_for_token(fmt_token)
          furthest_block.children.dup.each { |child| new_formatting.append_child(child) }
          furthest_block.append_child(new_formatting)

          @active_formatting_elements.delete(formatting_element)
          bookmark = bookmark.clamp(0, @active_formatting_elements.size)
          @active_formatting_elements.insert(bookmark, new_formatting)

          stack_of_open_elements.remove(formatting_element)
          stack_of_open_elements.insert_immediately_below(furthest_block, new_formatting)
        end
      end
    end
  end
end
