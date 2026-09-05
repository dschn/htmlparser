# frozen_string_literal: true

module HTMLParser
  class TreeConstruction
    # §13.2.6.4.9–.15 — table insertion modes (+ in table text).
    module TableModes
      private

      # §13.2.6.4.9 The "in table" insertion mode
      def process_in_table(token)
        case token
        when CharacterToken
          if current_node&.html? && %w[table tbody tfoot thead tr template].include?(current_node.name)
            @pending_table_character_tokens = []
            @original_insertion_mode = @insertion_mode
            @insertion_mode = :in_table_text
            anything_else_reprocess(token)
          else
            in_table_anything_else(token)
          end
        when CommentToken
          insert_comment(token)
        when DocTypeToken
          parse_error("unexpected-doctype")
        when StartTagToken
          process_in_table_start_tag(token)
        when EndTagToken
          process_in_table_end_tag(token)
        when EOFToken
          # Template EOF must run in-template rules; otherwise html5lib wants eof-in-table.
          if @template_insertion_modes.any?
            process_in_template(token)
          else
            parse_error("eof-in-table") unless current_node&.html? && current_node.name == "html"
            stop_parsing
          end
        end
      end

      # §13.2.6.4.9 — start tags in "in table".
      def process_in_table_start_tag(token)
        case token.name
        when "caption"
          clear_stack_back_to_table_context
          @active_formatting_elements << :marker
          insert_html_element(token)
          @insertion_mode = :in_caption
        when "colgroup"
          clear_stack_back_to_table_context
          insert_html_element(token)
          @insertion_mode = :in_column_group
        when "col"
          clear_stack_back_to_table_context
          insert_html_element(StartTagToken.new("colgroup"))
          @insertion_mode = :in_column_group
          anything_else_reprocess(token)
        when "tbody", "tfoot", "thead"
          clear_stack_back_to_table_context
          insert_html_element(token)
          @insertion_mode = :in_table_body
        when "td", "th", "tr"
          clear_stack_back_to_table_context
          insert_html_element(StartTagToken.new("tbody"))
          @insertion_mode = :in_table_body
          anything_else_reprocess(token)
        when "table"
          parse_error("unexpected-start-tag-implies-end-tag")
          return unless stack_of_open_elements.in_table_scope?("table")

          stack_of_open_elements.pop_until("table")
          reset_insertion_mode_appropriately
          anything_else_reprocess(token)
        when "style", "script", "template"
          process_in_head(token)
        when "input"
          type = token.attributes.find { |a| a[:name] == "type" }&.dig(:value)
          if type.nil? || !type.casecmp?("hidden")
            in_table_anything_else(token)
          else
            parse_error("unexpected-hidden-input-in-table")
            insert_html_element(token)
            stack_of_open_elements.pop
            acknowledge_self_closing_flag(token)
          end
        when "form"
          parse_error("unexpected-form-in-table")
          return if stack_of_open_elements.include_html?("template") || @form_element

          @form_element = insert_html_element(token)
          stack_of_open_elements.pop
        else
          in_table_anything_else(token)
        end
      end

      # §13.2.6.4.9 — end tags in "in table".
      def process_in_table_end_tag(token)
        case token.name
        when "table"
          unless stack_of_open_elements.in_table_scope?("table")
            parse_error("unexpected-end-tag")
            return
          end
          generate_implied_end_tags
          unless current_node&.html? && current_node.name == "table"
            parse_error("end-tag-too-early-named")
          end
          stack_of_open_elements.pop_until("table")
          reset_insertion_mode_appropriately
        when "body", "caption", "col", "colgroup", "html", "tbody", "td", "tfoot", "th", "thead", "tr"
          parse_error("unexpected-end-tag")
        when "template"
          process_in_head(token)
        else
          in_table_anything_else(token)
        end
      end

      def in_table_anything_else(token)
        # Modern html5lib/WPT fixtures use foster-parenting-*; older ones still say
        # *-implies-table-voodoo. Emit the modern names; harness equates both.
        code = case token
        when StartTagToken then "foster-parenting-start-tag"
        when EndTagToken then "foster-parenting-end-tag"
        when CharacterToken then "foster-parenting-character"
        else "unexpected-token-in-table"
        end
        # Character foster-parenting errors use the post-character cursor (nil token).
        parse_error(code, token.is_a?(CharacterToken) ? nil : token)
        process_as_in_body_with_foster_parenting(token)
      end

      # §13.2.6.4.10 The "in table text" insertion mode
      def process_in_table_text(token)
        case token
        when CharacterToken
          if token.value == "\u0000"
            parse_error("invalid-codepoint-in-table-text")
          else
            @pending_table_character_tokens << token.value
            @pending_table_character_line = tokenizer.input_stream_line
            @pending_table_character_column = tokenizer.input_stream_column
          end
        else
          flush_pending_table_character_tokens
          @insertion_mode = @original_insertion_mode
          anything_else_reprocess(token)
        end
      end

      def flush_pending_table_character_tokens
        pending = @pending_table_character_tokens.join
        @pending_table_character_tokens = []
        @pending_table_character_line = nil
        @pending_table_character_column = nil
        return if pending.empty?

        if whitespace_string?(pending)
          insert_character(pending)
        else
          # WPT: one foster-parenting-character(-in-table) per buffered character,
          # located at the token that flushed in-table-text.
          pending.length.times { parse_error("foster-parenting-character", nil) }
          pending.each_char do |char|
            process_as_in_body_with_foster_parenting(CharacterToken.new(char))
          end
        end
      end

      # §13.2.6.4.11 The "in caption" insertion mode
      def process_in_caption(token)
        case token
        when EndTagToken
          case token.name
          when "caption"
            close_caption
          when "table"
            return unless close_caption

            anything_else_reprocess(token)
          when "body", "col", "colgroup", "html", "tbody", "td", "tfoot", "th", "thead", "tr"
            parse_error("unexpected-end-tag")
          else
            process_in_body(token)
          end
        when StartTagToken
          if %w[caption col colgroup tbody td tfoot th thead tr].include?(token.name)
            return unless close_caption

            anything_else_reprocess(token)
          else
            process_in_body(token)
          end
        else
          process_in_body(token)
        end
      end

      def close_caption
        unless stack_of_open_elements.in_table_scope?("caption")
          parse_error("unexpected-end-tag")
          return false
        end
        generate_implied_end_tags
        parse_error("expected-one-end-tag-but-got-another") unless current_node&.name == "caption"
        stack_of_open_elements.pop_until("caption")
        clear_active_formatting_elements_to_last_marker
        @insertion_mode = :in_table
        true
      end

      # §13.2.6.4.12 The "in column group" insertion mode
      def process_in_column_group(token)
        case token
        when CharacterToken
          if whitespace_character_token?(token)
            insert_character(token.value)
          else
            leave_column_group_and_reprocess(token)
          end
        when CommentToken
          insert_comment(token)
        when DocTypeToken
          parse_error("unexpected-doctype")
        when StartTagToken
          case token.name
          when "html"
            process_in_body(token)
          when "col"
            insert_html_element(token)
            stack_of_open_elements.pop
            acknowledge_self_closing_flag(token)
          when "template"
            process_in_head(token)
          else
            leave_column_group_and_reprocess(token)
          end
        when EndTagToken
          case token.name
          when "colgroup"
            if current_node&.html? && current_node.name == "colgroup"
              stack_of_open_elements.pop
              @insertion_mode = :in_table
            else
              parse_error("unexpected-end-tag")
            end
          when "col"
            parse_error("unexpected-end-tag")
          when "template"
            process_in_head(token)
          else
            leave_column_group_and_reprocess(token)
          end
        when EOFToken
          process_in_body(token)
        end
      end

      def leave_column_group_and_reprocess(token)
        unless current_node&.html? && current_node.name == "colgroup"
          parse_error("unexpected-token")
          return
        end
        stack_of_open_elements.pop
        @insertion_mode = :in_table
        anything_else_reprocess(token)
      end

      # §13.2.6.4.13 The "in table body" insertion mode
      def process_in_table_body(token)
        case token
        when StartTagToken
          case token.name
          when "tr"
            clear_stack_back_to_table_body_context
            insert_html_element(token)
            @insertion_mode = :in_row
          when "th", "td"
            # html5lib: unexpected-cell-in-table-body
            parse_error("unexpected-cell-in-table-body")
            clear_stack_back_to_table_body_context
            insert_html_element(StartTagToken.new("tr"))
            @insertion_mode = :in_row
            anything_else_reprocess(token)
          when "caption", "col", "colgroup", "tbody", "tfoot", "thead"
            # §13.2.6.4.13 — not in table-body scope: parse error; ignore.
            # html5lib: unexpected-start-tag (or nameless XXX-undefined-error).
            unless stack_of_open_elements.in_table_scope?(%w[tbody thead tfoot])
              parse_error("unexpected-start-tag")
              return
            end

            clear_stack_back_to_table_body_context
            stack_of_open_elements.pop
            @insertion_mode = :in_table
            anything_else_reprocess(token)
          else
            process_in_table(token)
          end
        when EndTagToken
          case token.name
          when "tbody", "tfoot", "thead"
            unless stack_of_open_elements.in_table_scope?(token.name)
              parse_error("unexpected-end-tag-in-table-body")
              return
            end
            clear_stack_back_to_table_body_context
            stack_of_open_elements.pop
            @insertion_mode = :in_table
          when "table"
            # §13.2.6.4.13 — no tbody/thead/tfoot in table scope: parse error; ignore.
            unless stack_of_open_elements.in_table_scope?(%w[tbody thead tfoot])
              parse_error("unexpected-end-tag")
              return
            end

            clear_stack_back_to_table_body_context
            stack_of_open_elements.pop
            @insertion_mode = :in_table
            anything_else_reprocess(token)
          when "body", "caption", "col", "colgroup", "html", "td", "th", "tr"
            parse_error("unexpected-end-tag-in-table-body")
          else
            process_in_table(token)
          end
        else
          process_in_table(token)
        end
      end

      # §13.2.6.4.14 The "in row" insertion mode
      def process_in_row(token)
        case token
        when StartTagToken
          case token.name
          when "th", "td"
            clear_stack_back_to_table_row_context
            insert_html_element(token)
            @insertion_mode = :in_cell
            @active_formatting_elements << :marker
          when "caption", "col", "colgroup", "tbody", "tfoot", "thead", "tr"
            # §13.2.6.4.14 — no tr in table scope: parse error; ignore.
            # html5lib: unexpected-start-tag (or nameless XXX-undefined-error).
            unless stack_of_open_elements.in_table_scope?("tr")
              parse_error("unexpected-start-tag")
              return
            end

            clear_stack_back_to_table_row_context
            stack_of_open_elements.pop
            @insertion_mode = :in_table_body
            anything_else_reprocess(token)
          else
            process_in_table(token)
          end
        when EndTagToken
          case token.name
          when "tr"
            unless stack_of_open_elements.in_table_scope?("tr")
              parse_error("unexpected-end-tag")
              return
            end
            clear_stack_back_to_table_row_context
            stack_of_open_elements.pop
            @insertion_mode = :in_table_body
          when "table"
            # §13.2.6.4.14 — no tr in table scope: parse error; ignore.
            unless stack_of_open_elements.in_table_scope?("tr")
              parse_error("unexpected-end-tag")
              return
            end

            clear_stack_back_to_table_row_context
            stack_of_open_elements.pop
            @insertion_mode = :in_table_body
            anything_else_reprocess(token)
          when "tbody", "tfoot", "thead"
            unless stack_of_open_elements.in_table_scope?(token.name)
              parse_error("unexpected-end-tag")
              return
            end
            return unless stack_of_open_elements.in_table_scope?("tr")

            clear_stack_back_to_table_row_context
            stack_of_open_elements.pop
            @insertion_mode = :in_table_body
            anything_else_reprocess(token)
          when "body", "caption", "col", "colgroup", "html", "td", "th"
            parse_error("unexpected-end-tag-in-table-row")
          else
            process_in_table(token)
          end
        else
          process_in_table(token)
        end
      end

      # §13.2.6.4.15 The "in cell" insertion mode
      def process_in_cell(token)
        case token
        when EndTagToken
          case token.name
          when "td", "th"
            unless stack_of_open_elements.in_table_scope?(token.name)
              parse_error("unexpected-end-tag")
              return
            end
            generate_implied_end_tags
            parse_error("unexpected-cell-end-tag") unless current_node&.name == token.name
            stack_of_open_elements.pop_until(token.name)
            clear_active_formatting_elements_to_last_marker
            @insertion_mode = :in_row
          when "body", "caption", "col", "colgroup", "html"
            parse_error("unexpected-end-tag")
          when "table", "tbody", "tfoot", "thead", "tr"
            unless stack_of_open_elements.in_table_scope?(token.name)
              parse_error("unexpected-end-tag")
              return
            end
            close_the_cell
            anything_else_reprocess(token)
          else
            process_in_body(token)
          end
        when StartTagToken
          if %w[caption col colgroup tbody td tfoot th thead tr].include?(token.name)
            unless stack_of_open_elements.in_table_scope?(%w[td th])
              parse_error("unexpected-start-tag")
              return
            end
            close_the_cell
            anything_else_reprocess(token)
          else
            process_in_body(token)
          end
        else
          process_in_body(token)
        end
      end
    end
  end
end
