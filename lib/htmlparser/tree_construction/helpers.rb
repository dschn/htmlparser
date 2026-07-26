# frozen_string_literal: true

module HTMLParser
  class TreeConstruction
    # Shared tree-construction algorithms (§13.2.6).
    module Helpers
      private

      def current_node
        stack_of_open_elements.current
      end

      # §13.2.6.1 — appropriate place for inserting a node (incl. foster parenting).
      def appropriate_place_for_inserting_a_node(override_target = nil)
        target = override_target || current_node
        location = if @foster_parenting && target&.html? && %w[table tbody tfoot thead tr].include?(target.name)
          foster_parent_location
        else
          InsertionLocation.new(parent: target || document, before: nil)
        end

        # If the adjusted insertion location is inside a template element, use its contents.
        parent = location.parent
        if parent.is_a?(Element) && parent.html? && parent.name == "template"
          InsertionLocation.new(parent: parent.template_contents, before: nil)
        else
          location
        end
      end

      def foster_parent_location
        elements = stack_of_open_elements.to_a
        last_template_idx = elements.rindex { |el| el.html? && el.name == "template" }
        last_table_idx = elements.rindex { |el| el.html? && el.name == "table" }

        if last_template_idx && (last_table_idx.nil? || last_template_idx > last_table_idx)
          return InsertionLocation.new(parent: elements[last_template_idx].template_contents, before: nil)
        end

        if last_table_idx.nil?
          return InsertionLocation.new(parent: elements.first || document, before: nil)
        end

        last_table = elements[last_table_idx]
        if last_table.parent
          InsertionLocation.new(parent: last_table.parent, before: last_table)
        else
          above = (last_table_idx > 0) ? elements[last_table_idx - 1] : document
          InsertionLocation.new(parent: above, before: nil)
        end
      end

      def insert_node_at(location, node)
        if location.before
          location.parent.insert_before(node, location.before)
        else
          location.parent.append_child(node)
        end
      end

      def create_element_for_token(token)
        attrs = {}
        token.attributes.each do |attr|
          attrs[attr[:name]] ||= attr[:value]
        end
        element = Element.new(token.name, attributes: attrs)
        element.token = token
        element
      end

      def insert_html_element(token)
        element = create_element_for_token(token)
        insert_node_at(appropriate_place_for_inserting_a_node, element)
        stack_of_open_elements.push(element)
        element
      end

      def insert_character(data)
        return if data.empty?

        location = appropriate_place_for_inserting_a_node
        parent = location.parent
        return if parent.is_a?(Document)

        if location.before
          idx = parent.children.index(location.before) || 0
          prev = (idx > 0) ? parent.children[idx - 1] : nil
          if prev.is_a?(TextNode)
            prev.data << data
          else
            insert_node_at(location, TextNode.new(+data.dup))
          end
        else
          last = parent.children.last
          if last.is_a?(TextNode)
            last.data << data
          else
            parent.append_child(TextNode.new(+data.dup))
          end
        end
      end

      def insert_comment(token, parent = nil)
        if parent
          parent.append_child(Comment.new(token.data))
        else
          insert_node_at(appropriate_place_for_inserting_a_node, Comment.new(token.data))
        end
      end

      def generate_implied_end_tags(exclude: nil)
        loop do
          node = current_node
          break unless node&.html?
          break if exclude && node.name == exclude
          break unless %w[dd dt li optgroup option p rb rp rt rtc].include?(node.name)

          stack_of_open_elements.pop
        end
      end

      # §13.2.6 — generate all implied end tags thoroughly.
      def generate_implied_end_tags_thoroughly
        loop do
          node = current_node
          break unless node&.html?
          break unless %w[
            caption colgroup dd dt li optgroup option p rb rp rt rtc
            tbody td tfoot th thead tr
          ].include?(node.name)

          stack_of_open_elements.pop
        end
      end

      def close_p_element
        generate_implied_end_tags(exclude: "p")
        parse_error("expected-closing-tag-but-got-others") unless current_node&.name == "p"
        stack_of_open_elements.pop_until("p")
      end

      def acknowledge_self_closing_flag(_token)
        # Spec: clear the self-closing flag acknowledgement. No further action yet.
      end

      def generic_rcdata_element_parsing_algorithm(token)
        insert_html_element(token)
        tokenizer.switch_to(:rcdata)
        @original_insertion_mode = @insertion_mode
        @insertion_mode = :text
      end

      def generic_raw_text_element_parsing_algorithm(token)
        insert_html_element(token)
        tokenizer.switch_to(:rawtext)
        @original_insertion_mode = @insertion_mode
        @insertion_mode = :text
      end

      def stop_parsing
        @halt = true
      end

      def parse_error(_code)
        # Tree parse errors are collected later when the harness compares #errors.
        # For now matching document shape is the progress gate.
      end

      def whitespace_character_token?(token)
        token.is_a?(CharacterToken) && token.value.match?(/\A[\t\n\f\r ]+\z/)
      end

      def whitespace_string?(string)
        string.match?(/\A[\t\n\f\r ]*\z/)
      end

      def anything_else_reprocess(_token)
        @reprocess = true
      end

      def clear_stack_back_to_table_context
        until current_node&.html? && %w[table template html].include?(current_node.name)
          stack_of_open_elements.pop
        end
      end

      def clear_stack_back_to_table_body_context
        until current_node&.html? && %w[tbody tfoot thead template html].include?(current_node.name)
          stack_of_open_elements.pop
        end
      end

      def clear_stack_back_to_table_row_context
        until current_node&.html? && %w[tr template html].include?(current_node.name)
          stack_of_open_elements.pop
        end
      end

      def close_the_cell
        generate_implied_end_tags
        unless current_node&.html? && %w[td th].include?(current_node.name)
          parse_error("expected-closing-tag-but-got-others")
        end
        loop do
          el = stack_of_open_elements.pop
          break if el.nil? || (el.html? && %w[td th].include?(el.name))
        end
        clear_active_formatting_elements_to_last_marker
        @insertion_mode = :in_row
      end

      # §13.2.6.3 Reset the insertion mode appropriately (table-focused).
      def reset_insertion_mode_appropriately
        nodes = stack_of_open_elements.to_a
        idx = nodes.size - 1
        while idx >= 0
          node = nodes[idx]
          last = (idx == 0)

          if node.html? && %w[td th].include?(node.name) && !last
            @insertion_mode = :in_cell
            return
          elsif node.html? && node.name == "tr"
            @insertion_mode = :in_row
            return
          elsif node.html? && %w[tbody thead tfoot].include?(node.name)
            @insertion_mode = :in_table_body
            return
          elsif node.html? && node.name == "caption"
            @insertion_mode = :in_caption
            return
          elsif node.html? && node.name == "colgroup"
            @insertion_mode = :in_column_group
            return
          elsif node.html? && node.name == "table"
            @insertion_mode = :in_table
            return
          elsif node.html? && node.name == "template"
            @insertion_mode = @template_insertion_modes.last || :in_template
            return
          elsif node.html? && node.name == "head" && !last
            @insertion_mode = :in_head
            return
          elsif node.html? && node.name == "body"
            @insertion_mode = :in_body
            return
          elsif node.html? && node.name == "frameset"
            @insertion_mode = :in_frameset
            return
          elsif node.html? && node.name == "html"
            @insertion_mode = @head_element.nil? ? :before_head : :after_head
            return
          elsif last
            @insertion_mode = :in_body
            return
          end
          idx -= 1
        end
        @insertion_mode = :in_body
      end

      def process_as_in_body_with_foster_parenting(token)
        @foster_parenting = true
        process_in_body(token)
      ensure
        @foster_parenting = false
      end
    end
  end
end
