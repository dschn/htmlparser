# frozen_string_literal: true

module HTMLParser
  class TreeConstruction
    # §13.2.6 insertion modes (early set: initial … in body basics + text + after body).
    module InsertionModes
      private

      # §13.2.6.4.1 The "initial" insertion mode
      def process_initial(token)
        case token
        when CharacterToken
          return if whitespace_character_token?(token)

          parse_error("expected-doctype-but-got-chars")
          document.quirks_mode = :quirks
          @insertion_mode = :before_html
          anything_else_reprocess(token)
        when CommentToken
          insert_comment(token, document)
        when DocTypeToken
          name = token.name || ""
          public_id = token.public_identifier
          system_id = token.system_identifier
          # §13.2.6.4.1 — parse error unless name is html and ids are missing
          # (system id may be "about:legacy-compat"). html5lib: unknown-doctype.
          html_name = name.downcase == "html"
          legacy_system = system_id.nil? || system_id == "about:legacy-compat"
          parse_error("unknown-doctype") unless html_name && public_id.nil? && legacy_system
          document.append_child(
            DocumentType.new(name, public_id, system_id)
          )
          # §13.2.6.4.1 — quirks-mode-doctypes (public/system id lists).
          document.quirks_mode = quirks_mode_for_doctype(token)
          @insertion_mode = :before_html
        when EOFToken
          parse_error("expected-doctype-but-got-eof")
          document.quirks_mode = :quirks
          @insertion_mode = :before_html
          anything_else_reprocess(token)
        else
          code = if token.is_a?(StartTagToken)
            "expected-doctype-but-got-start-tag"
          else
            "expected-doctype-but-got-end-tag"
          end
          parse_error(code)
          document.quirks_mode = :quirks
          @insertion_mode = :before_html
          anything_else_reprocess(token)
        end
      end

      # §13.2.6.4.2 The "before html" insertion mode
      def process_before_html(token)
        case token
        when DocTypeToken
          parse_error("unexpected-doctype")
        when CommentToken
          insert_comment(token, document)
        when CharacterToken
          return if whitespace_character_token?(token)

          insert_html_html_and_reprocess(token)
        when StartTagToken
          if token.name == "html"
            insert_html_element(token)
            @insertion_mode = :before_head
          else
            insert_html_html_and_reprocess(token)
          end
        when EndTagToken
          if %w[head body html br].include?(token.name)
            insert_html_html_and_reprocess(token)
          else
            parse_error("unexpected-end-tag-before-html")
          end
        when EOFToken
          insert_html_html_and_reprocess(token)
        end
      end

      def insert_html_html_and_reprocess(token)
        element = Element.new("html")
        document.append_child(element)
        stack_of_open_elements.push(element)
        @insertion_mode = :before_head
        anything_else_reprocess(token)
      end

      # §13.2.6.4.3 The "before head" insertion mode
      def process_before_head(token)
        case token
        when CharacterToken
          return if whitespace_character_token?(token)

          insert_head_and_reprocess(token)
        when CommentToken
          insert_comment(token)
        when DocTypeToken
          parse_error("unexpected-doctype")
        when StartTagToken
          case token.name
          when "html"
            process_in_body(token)
          when "head"
            @head_element = insert_html_element(token)
            @insertion_mode = :in_head
          else
            insert_head_and_reprocess(token)
          end
        when EndTagToken
          if %w[head body html br].include?(token.name)
            insert_head_and_reprocess(token)
          else
            parse_error("unexpected-end-tag")
          end
        when EOFToken
          insert_head_and_reprocess(token)
        end
      end

      def insert_head_and_reprocess(token)
        @head_element = insert_html_element(StartTagToken.new("head"))
        @insertion_mode = :in_head
        anything_else_reprocess(token)
      end

      # §13.2.6.4.4 The "in head" insertion mode
      def process_in_head(token)
        case token
        when CharacterToken
          if whitespace_character_token?(token)
            insert_character(token.value)
          else
            anything_else_in_head(token)
          end
        when CommentToken
          insert_comment(token)
        when DocTypeToken
          parse_error("unexpected-doctype")
        when StartTagToken
          case token.name
          when "html"
            process_in_body(token)
          when "base", "basefont", "bgsound", "link"
            insert_html_element(token)
            stack_of_open_elements.pop
            acknowledge_self_closing_flag(token)
          when "meta"
            insert_html_element(token)
            stack_of_open_elements.pop
            acknowledge_self_closing_flag(token)
          when "title"
            generic_rcdata_element_parsing_algorithm(token)
          when "noscript"
            # Scripting disabled: insert and switch to in head noscript.
            insert_html_element(token)
            @insertion_mode = :in_head_noscript
          when "noframes", "style"
            generic_raw_text_element_parsing_algorithm(token)
          when "script"
            insert_html_element(token)
            tokenizer.switch_to(:script_data)
            @original_insertion_mode = @insertion_mode
            @insertion_mode = :text
          when "template"
            # §13.2.6.4.4 — template start tag (non–declarative-shadow path).
            @active_formatting_elements << :marker
            @frameset_ok = false
            @insertion_mode = :in_template
            @template_insertion_modes << :in_template
            insert_html_element(token)
          when "head"
            parse_error("unexpected-start-tag")
          else
            anything_else_in_head(token)
          end
        when EndTagToken
          case token.name
          when "head"
            stack_of_open_elements.pop
            @insertion_mode = :after_head
          when "body", "html", "br"
            anything_else_in_head(token)
          when "template"
            close_template_element
          else
            parse_error("unexpected-end-tag")
          end
        when EOFToken
          anything_else_in_head(token)
        end
      end

      def anything_else_in_head(token)
        stack_of_open_elements.pop
        @insertion_mode = :after_head
        anything_else_reprocess(token)
      end

      # §13.2.6.4.4 — template end tag.
      def close_template_element
        unless stack_of_open_elements.include_html?("template")
          parse_error("unexpected-end-tag")
          return
        end
        generate_implied_end_tags_thoroughly
        unless current_node&.html? && current_node.name == "template"
          parse_error("expected-closing-tag-but-got-others")
        end
        stack_of_open_elements.pop_until("template")
        clear_active_formatting_elements_to_last_marker
        @template_insertion_modes.pop
        reset_insertion_mode_appropriately
      end

      # §13.2.6.4.5 The "in head noscript" insertion mode (scripting disabled)
      def process_in_head_noscript(token)
        case token
        when CharacterToken
          if whitespace_character_token?(token)
            process_in_head(token)
          else
            parse_error("unexpected-char")
            stack_of_open_elements.pop
            @insertion_mode = :in_head
            anything_else_reprocess(token)
          end
        when CommentToken, DocTypeToken
          process_in_head(token)
        when StartTagToken
          case token.name
          when "html"
            process_in_body(token)
          when "basefont", "bgsound", "link", "meta", "noframes", "style"
            process_in_head(token)
          when "head", "noscript"
            parse_error("unexpected-start-tag")
          else
            parse_error("unexpected-start-tag")
            stack_of_open_elements.pop
            @insertion_mode = :in_head
            anything_else_reprocess(token)
          end
        when EndTagToken
          case token.name
          when "noscript"
            stack_of_open_elements.pop
            @insertion_mode = :in_head
          when "br"
            parse_error("unexpected-end-tag")
            stack_of_open_elements.pop
            @insertion_mode = :in_head
            anything_else_reprocess(token)
          else
            parse_error("unexpected-end-tag")
          end
        when EOFToken
          parse_error("eof-in-head-noscript")
          stack_of_open_elements.pop
          @insertion_mode = :in_head
          anything_else_reprocess(token)
        end
      end

      # §13.2.6.4.6 The "after head" insertion mode
      def process_after_head(token)
        case token
        when CharacterToken
          if whitespace_character_token?(token)
            insert_character(token.value)
          else
            insert_body_and_reprocess(token)
          end
        when CommentToken
          insert_comment(token)
        when DocTypeToken
          parse_error("unexpected-doctype")
        when StartTagToken
          case token.name
          when "html"
            process_in_body(token)
          when "body"
            insert_html_element(token)
            @frameset_ok = false
            @insertion_mode = :in_body
          when "frameset"
            insert_html_element(token)
            @insertion_mode = :in_frameset
          when "base", "basefont", "bgsound", "link", "meta", "noframes", "script", "style", "template", "title"
            parse_error("unexpected-start-tag-out-of-my-head")
            stack_of_open_elements.push(@head_element) if @head_element
            process_in_head(token)
            stack_of_open_elements.remove(@head_element) if @head_element
          when "head"
            parse_error("unexpected-start-tag")
          else
            insert_body_and_reprocess(token)
          end
        when EndTagToken
          case token.name
          when "body", "html", "br"
            insert_body_and_reprocess(token)
          when "template"
            process_in_head(token)
          else
            parse_error("unexpected-end-tag")
          end
        when EOFToken
          insert_body_and_reprocess(token)
        end
      end

      def insert_body_and_reprocess(token)
        insert_html_element(StartTagToken.new("body"))
        @insertion_mode = :in_body
        anything_else_reprocess(token)
      end

      # §13.2.6.4.7 The "in body" insertion mode (subset)
      def process_in_body(token)
        case token
        when CharacterToken
          if @ignore_next_lf
            @ignore_next_lf = false
            return if token.value == "\n"
          end
          if token.value == "\u0000"
            # Tokenizer already reported invalid-codepoint; html5lib adds a mode name.
            code = if stack_of_open_elements.include_html?("select")
              "invalid-codepoint-in-select"
            else
              "invalid-codepoint-in-body"
            end
            parse_error(code)
            return
          end
          reconstruct_active_formatting_elements
          insert_character(token.value)
          @frameset_ok = false unless whitespace_character_token?(token)
        when CommentToken
          insert_comment(token)
        when DocTypeToken
          parse_error("unexpected-doctype")
        when StartTagToken
          process_in_body_start_tag(token)
        when EndTagToken
          process_in_body_end_tag(token)
        when EOFToken
          if @template_insertion_modes.any?
            process_in_template(token)
          else
            # §13.2.6.4.7 — EOF in body: parse error if a non-exempt node is open.
            # html5lib names this expected-closing-tag-but-got-eof.
            if stack_of_open_elements.include_html?("select")
              parse_error("eof-in-select")
            elsif !stack_of_open_elements.to_a.all? { |el| eof_in_body_allowed?(el) }
              parse_error("expected-closing-tag-but-got-eof")
            end
            stop_parsing
          end
        end
      end

      def eof_in_body_allowed?(element)
        return false unless element.is_a?(Element) && element.html?

        %w[
          dd dt li optgroup option p rb rp rt rtc
          tbody td tfoot th thead tr body html
        ].include?(element.name)
      end

      def process_in_body_start_tag(token)
        case token.name
        when "html"
          parse_error("non-html-root")
          return if stack_of_open_elements.include_html?("template")

          html = stack_of_open_elements.first_html("html")
          return unless html

          token.attributes.each do |attr|
            html.attributes[attr[:name]] ||= attr[:value]
          end
        when "base", "basefont", "bgsound", "link", "meta", "noframes", "script", "style", "template", "title"
          process_in_head(token)
        when "body"
          parse_error("unexpected-start-tag")
          body = stack_of_open_elements.first_html("body")
          return if body.nil? || stack_of_open_elements.to_a.size == 1
          return if stack_of_open_elements.include_html?("template")

          @frameset_ok = false
          token.attributes.each do |attr|
            body.attributes[attr[:name]] ||= attr[:value]
          end
        when "frameset"
          # §13.2.6.4.7 — frameset start tag (may replace the body).
          parse_error("unexpected-start-tag")
          elements = stack_of_open_elements.to_a
          second = elements[1]
          if elements.size <= 1 || !(second&.html? && second.name == "body")
            # ignore (fragment case / template)
          elsif !@frameset_ok
            # ignore
          else
            second.parent&.remove_child(second)
            loop do
              break if stack_of_open_elements.to_a.size <= 1
              break if current_node&.html? && current_node.name == "html"

              stack_of_open_elements.pop
            end
            insert_html_element(token)
            @insertion_mode = :in_frameset
          end
        when "address", "article", "aside", "blockquote", "center", "details", "dialog",
          "dir", "div", "dl", "fieldset", "figcaption", "figure", "footer", "header",
          "hgroup", "main", "menu", "nav", "ol", "p", "search", "section", "summary", "ul"
          close_p_element if stack_of_open_elements.in_button_scope?("p")
          insert_html_element(token)
        when "h1", "h2", "h3", "h4", "h5", "h6"
          close_p_element if stack_of_open_elements.in_button_scope?("p")
          if current_node&.html? && %w[h1 h2 h3 h4 h5 h6].include?(current_node.name)
            parse_error("unexpected-start-tag")
            stack_of_open_elements.pop
          end
          insert_html_element(token)
        when "pre", "listing"
          close_p_element if stack_of_open_elements.in_button_scope?("p")
          insert_html_element(token)
          @frameset_ok = false
          # Leading LF ignored by peeking next character — handled loosely: skip if next is LF via flag
          @ignore_next_lf = true
        when "form"
          if @form_element
            parse_error("unexpected-start-tag")
          else
            close_p_element if stack_of_open_elements.in_button_scope?("p")
            @form_element = insert_html_element(token)
          end
        when "li"
          @frameset_ok = false
          stack_of_open_elements.to_a.reverse_each do |node|
            if node.html? && node.name == "li"
              generate_implied_end_tags(exclude: "li")
              # html5lib routes this through the li end-tag path (end-tag-too-early).
              parse_error("end-tag-too-early") unless current_node&.name == "li"
              stack_of_open_elements.pop_until("li")
              break
            end
            break if node.html? && special_category?(node.name) && !%w[address div p].include?(node.name)
          end
          close_p_element if stack_of_open_elements.in_button_scope?("p")
          insert_html_element(token)
        when "dd", "dt"
          @frameset_ok = false
          stack_of_open_elements.to_a.reverse_each do |node|
            if node.html? && %w[dd dt].include?(node.name)
              generate_implied_end_tags(exclude: node.name)
              parse_error("end-tag-too-early") unless current_node&.name == node.name
              stack_of_open_elements.pop_until(node.name)
              break
            end
            break if node.html? && special_category?(node.name) && !%w[address div p].include?(node.name)
          end
          close_p_element if stack_of_open_elements.in_button_scope?("p")
          insert_html_element(token)
        when "plaintext"
          close_p_element if stack_of_open_elements.in_button_scope?("p")
          insert_html_element(token)
          tokenizer.switch_to(:plaintext)
        when "button"
          if stack_of_open_elements.in_scope?("button")
            parse_error("unexpected-start-tag-implies-end-tag")
            generate_implied_end_tags
            stack_of_open_elements.pop_until("button")
          end
          reconstruct_active_formatting_elements
          insert_html_element(token)
          @frameset_ok = false
        when "a"
          existing = find_formatting_element_after_last_marker("a")
          if existing
            parse_error("unexpected-start-tag-implies-end-tag")
            adoption_agency_algorithm(token)
            @active_formatting_elements.delete(existing)
            stack_of_open_elements.remove(existing)
          end
          reconstruct_active_formatting_elements
          element = insert_html_element(token)
          push_onto_list_of_active_formatting_elements(element)
        when "b", "big", "code", "em", "font", "i", "s", "small", "strike", "strong", "tt", "u"
          reconstruct_active_formatting_elements
          element = insert_html_element(token)
          push_onto_list_of_active_formatting_elements(element)
        when "nobr"
          reconstruct_active_formatting_elements
          if stack_of_open_elements.in_scope?("nobr")
            parse_error("unexpected-start-tag-implies-end-tag")
            adoption_agency_algorithm(token)
            reconstruct_active_formatting_elements
          end
          element = insert_html_element(token)
          push_onto_list_of_active_formatting_elements(element)
        when "applet", "marquee", "object"
          reconstruct_active_formatting_elements
          insert_html_element(token)
          @active_formatting_elements << :marker
          @frameset_ok = false
        when "table"
          # In quirks mode only, a table may be a descendant of a p.
          close_p_element if document.quirks_mode != :quirks && stack_of_open_elements.in_button_scope?("p")
          insert_html_element(token)
          @frameset_ok = false
          @insertion_mode = :in_table
        when "area", "br", "embed", "img", "keygen", "wbr"
          reconstruct_active_formatting_elements
          insert_html_element(token)
          stack_of_open_elements.pop
          acknowledge_self_closing_flag(token)
          @frameset_ok = false
        when "input"
          if fragment_context_is?("select")
            parse_error("unexpected-start-tag")
            return
          end
          if stack_of_open_elements.in_scope?("select")
            parse_error("unexpected-start-tag")
            stack_of_open_elements.pop_until("select")
          end
          reconstruct_active_formatting_elements
          insert_html_element(token)
          stack_of_open_elements.pop
          acknowledge_self_closing_flag(token)
          type = token.attributes.find { |a| a[:name] == "type" }&.dig(:value)&.downcase
          @frameset_ok = false unless type == "hidden"
        when "param", "source", "track"
          insert_html_element(token)
          stack_of_open_elements.pop
          acknowledge_self_closing_flag(token)
        when "hr"
          # §13.2.6.4.7 — hr may separate options inside select.
          close_p_element if stack_of_open_elements.in_button_scope?("p")
          if stack_of_open_elements.in_scope?("select")
            generate_implied_end_tags
            if stack_of_open_elements.in_scope?("option") || stack_of_open_elements.in_scope?("optgroup")
              parse_error("unexpected-start-tag")
            end
          end
          insert_html_element(token)
          stack_of_open_elements.pop
          acknowledge_self_closing_flag(token)
          @frameset_ok = false
        when "image"
          parse_error("unexpected-start-tag")
          token.name = "img"
          process_in_body_start_tag(token)
        when "textarea"
          insert_html_element(token)
          @ignore_next_lf = true
          tokenizer.switch_to(:rcdata)
          @original_insertion_mode = @insertion_mode
          @frameset_ok = false
          @insertion_mode = :text
        when "xmp"
          close_p_element if stack_of_open_elements.in_button_scope?("p")
          reconstruct_active_formatting_elements
          @frameset_ok = false
          generic_raw_text_element_parsing_algorithm(token)
        when "iframe"
          @frameset_ok = false
          generic_raw_text_element_parsing_algorithm(token)
        when "noembed"
          generic_raw_text_element_parsing_algorithm(token)
        when "select"
          # Living standard: select stays in "in body" (no separate select insertion mode).
          if fragment_context_is?("select")
            parse_error("unexpected-start-tag")
          elsif stack_of_open_elements.in_scope?("select")
            parse_error("unexpected-start-tag")
            stack_of_open_elements.pop_until("select")
          else
            reconstruct_active_formatting_elements
            insert_html_element(token)
            @frameset_ok = false
          end
        when "option"
          if stack_of_open_elements.in_scope?("select")
            generate_implied_end_tags(exclude: "optgroup")
          elsif current_node&.html? && current_node.name == "option"
            stack_of_open_elements.pop
          end
          reconstruct_active_formatting_elements
          insert_html_element(token)
        when "optgroup"
          if stack_of_open_elements.in_scope?("select")
            generate_implied_end_tags
          elsif current_node&.html? && current_node.name == "option"
            stack_of_open_elements.pop
          end
          reconstruct_active_formatting_elements
          insert_html_element(token)
        when "rb", "rtc"
          # §13.2.6.4.7 — ruby in scope: implied end tags; parse error if current ≠ ruby.
          if stack_of_open_elements.in_scope?("ruby")
            generate_implied_end_tags
            parse_error("XXX-undefined-error") unless current_node&.html? && current_node.name == "ruby"
          end
          insert_html_element(token)
        when "rp", "rt"
          # §13.2.6.4.7 — same, except rtc is not implied-closed.
          if stack_of_open_elements.in_scope?("ruby")
            generate_implied_end_tags(exclude: "rtc")
            parse_error("XXX-undefined-error") unless current_node&.html? && current_node.name == "ruby"
          end
          insert_html_element(token)
        when "math"
          reconstruct_active_formatting_elements
          enter_foreign(token, MATHML_NAMESPACE)
        when "svg"
          reconstruct_active_formatting_elements
          enter_foreign(token, SVG_NAMESPACE)
        when "caption", "col", "colgroup", "frame", "head", "tbody", "td", "tfoot", "th", "thead", "tr"
          code = if stack_of_open_elements.include_html?("select")
            "unexpected-start-tag-in-select"
          else
            "unexpected-start-tag"
          end
          parse_error(code)
        else
          reconstruct_active_formatting_elements
          insert_html_element(token)
        end
      end

      def process_in_body_end_tag(token)
        case token.name
        when "template"
          process_in_head(token)
        when "body"
          unless stack_of_open_elements.in_scope?("body")
            parse_error("unexpected-end-tag")
            return
          end
          # html5lib: expected-one-end-tag-but-got-another when a non-exempt node is open.
          parse_error("expected-one-end-tag-but-got-another") if body_end_tag_has_unclosed_node?
          @insertion_mode = :after_body
        when "html"
          unless stack_of_open_elements.in_scope?("body")
            parse_error("unexpected-end-tag")
            return
          end
          @insertion_mode = :after_body
          anything_else_reprocess(token)
        when "address", "article", "aside", "blockquote", "button", "center", "details",
          "dialog", "dir", "div", "dl", "fieldset", "figcaption", "figure", "footer",
          "header", "hgroup", "listing", "main", "menu", "nav", "ol", "pre", "search",
          "section", "summary", "ul"
          # html5lib endTagBlock: end-tag-too-early even when the element is not in
          # scope (e.g. </div> with a marquee current — marquee is a scope barrier).
          in_scope = stack_of_open_elements.in_scope?(token.name)
          generate_implied_end_tags if in_scope
          parse_error("end-tag-too-early") unless current_node&.name == token.name
          stack_of_open_elements.pop_until(token.name) if in_scope
        when "form"
          # §13.2.6.4.7 — end tag form (remove form from stack; leave descendants open).
          if stack_of_open_elements.in_scope?("template")
            @form_element = nil
            unless stack_of_open_elements.in_scope?("form")
              parse_error("unexpected-end-tag")
              return
            end
            generate_implied_end_tags
            parse_error("end-tag-too-early") unless current_node&.html? && current_node.name == "form"
            stack_of_open_elements.pop_until("form")
          else
            node = @form_element
            @form_element = nil
            if node.nil? || !stack_of_open_elements.element_in_scope?(node)
              parse_error("unexpected-end-tag")
              return
            end
            generate_implied_end_tags
            # html5lib: end-tag-too-early-ignored when form is not the current node.
            parse_error("end-tag-too-early-ignored") unless current_node.equal?(node)
            stack_of_open_elements.remove(node)
          end
        when "p"
          unless stack_of_open_elements.in_button_scope?("p")
            parse_error("unexpected-end-tag")
            insert_html_element(StartTagToken.new("p"))
          end
          close_p_element
        when "li"
          unless list_item_in_scope?
            parse_error("unexpected-end-tag")
            return
          end
          generate_implied_end_tags(exclude: "li")
          parse_error("end-tag-too-early") unless current_node&.name == "li"
          stack_of_open_elements.pop_until("li")
        when "dd", "dt"
          unless stack_of_open_elements.in_scope?(token.name)
            parse_error("unexpected-end-tag")
            return
          end
          generate_implied_end_tags(exclude: token.name)
          parse_error("end-tag-too-early") unless current_node&.name == token.name
          stack_of_open_elements.pop_until(token.name)
        when "h1", "h2", "h3", "h4", "h5", "h6"
          # html5lib emits end-tag-too-early even when no heading is in scope
          # (e.g. <p></h3>), then pops only if a heading is in scope.
          if stack_of_open_elements.in_scope?(%w[h1 h2 h3 h4 h5 h6])
            generate_implied_end_tags
          end
          parse_error("end-tag-too-early") unless current_node&.name == token.name
          if stack_of_open_elements.in_scope?(%w[h1 h2 h3 h4 h5 h6])
            loop do
              el = stack_of_open_elements.pop
              break if el.nil? || (el.html? && %w[h1 h2 h3 h4 h5 h6].include?(el.name))
            end
          end
        when "a", "b", "big", "code", "em", "font", "i", "nobr", "s", "small", "strike",
          "strong", "tt", "u"
          adoption_agency_algorithm(token)
        when "applet", "marquee", "object"
          in_scope = stack_of_open_elements.in_scope?(token.name)
          generate_implied_end_tags if in_scope
          parse_error("end-tag-too-early") unless current_node&.name == token.name
          if in_scope
            stack_of_open_elements.pop_until(token.name)
            clear_active_formatting_elements_to_last_marker
          end
        when "br"
          parse_error("unexpected-end-tag")
          process_in_body_start_tag(StartTagToken.new("br"))
        else
          any_other_end_tag(token)
        end
      end

      def any_other_end_tag(token)
        stack_of_open_elements.to_a.reverse_each do |node|
          if node.html? && node.name == token.name
            generate_implied_end_tags(exclude: token.name)
            # html5lib still reports unexpected-end-tag here (not end-tag-too-early).
            parse_error("unexpected-end-tag") unless current_node&.name == token.name
            loop do
              el = stack_of_open_elements.pop
              break if el.nil? || el.equal?(node)
            end
            break
          elsif node.html? && special_category?(node.name)
            parse_error("unexpected-end-tag")
            break
          end
        end
      end

      def list_item_in_scope?
        stack_of_open_elements.in_list_item_scope?("li")
      end

      # html5lib endTagBody: error if a node below html/body is not in the EOF-ok set.
      def body_end_tag_has_unclosed_node?
        exempt = %w[
          dd dt li optgroup option p rp rt rb rtc
          tbody td tfoot th thead tr body html
        ]
        stack_of_open_elements.to_a.drop(2).any? do |node|
          !(node.html? && exempt.include?(node.name))
        end
      end

      def special_category?(name)
        %w[
          address applet area article aside base basefont bgsound blockquote body br button
          caption center col colgroup dd details dir div dl dt embed fieldset figcaption
          figure footer form frame frameset h1 h2 h3 h4 h5 h6 head header hgroup hr html
          iframe img input keygen li link listing main marquee menu meta nav noembed noframes
          noscript object ol p param plaintext pre script section select source style summary
          table tbody td template textarea tfoot th thead title tr track ul wbr xmp
        ].include?(name)
      end

      # §13.2.6.4.16 The "in template" insertion mode
      def process_in_template(token)
        case token
        when CharacterToken, CommentToken, DocTypeToken
          process_in_body(token)
        when StartTagToken
          case token.name
          when "base", "basefont", "bgsound", "link", "meta", "noframes", "script", "style", "template", "title"
            process_in_head(token)
          when "caption", "colgroup", "tbody", "tfoot", "thead"
            switch_current_template_insertion_mode(:in_table)
            anything_else_reprocess(token)
          when "col"
            switch_current_template_insertion_mode(:in_column_group)
            anything_else_reprocess(token)
          when "tr"
            switch_current_template_insertion_mode(:in_table_body)
            anything_else_reprocess(token)
          when "td", "th"
            switch_current_template_insertion_mode(:in_row)
            anything_else_reprocess(token)
          else
            switch_current_template_insertion_mode(:in_body)
            anything_else_reprocess(token)
          end
        when EndTagToken
          case token.name
          when "template"
            process_in_head(token)
          else
            parse_error("unexpected-end-tag")
          end
        when EOFToken
          unless stack_of_open_elements.include_html?("template")
            stop_parsing
            return
          end
          parse_error("eof-in-template")
          stack_of_open_elements.pop_until("template")
          clear_active_formatting_elements_to_last_marker
          @template_insertion_modes.pop
          reset_insertion_mode_appropriately
          anything_else_reprocess(token)
        end
      end

      def switch_current_template_insertion_mode(mode)
        @template_insertion_modes.pop
        @template_insertion_modes << mode
        @insertion_mode = mode
      end

      # §13.2.6.4.8 The "text" insertion mode
      def process_text(token)
        case token
        when CharacterToken
          if @ignore_next_lf && token.value == "\n"
            @ignore_next_lf = false
            return
          end
          @ignore_next_lf = false
          insert_character(token.value)
        when EOFToken
          parse_error("eof-in-text")
          stack_of_open_elements.pop
          @insertion_mode = @original_insertion_mode
          anything_else_reprocess(token)
        when EndTagToken
          stack_of_open_elements.pop
          @insertion_mode = @original_insertion_mode
        else
          # Start tags should not appear in text mode from a correct tokenizer.
          stack_of_open_elements.pop
          @insertion_mode = @original_insertion_mode
          anything_else_reprocess(token)
        end
      end

      # §13.2.6.4.19 / .22 — after body (minimal)
      def process_after_body(token)
        case token
        when CharacterToken
          if whitespace_character_token?(token)
            process_in_body(token)
          else
            parse_error("unexpected-char-after-body")
            @insertion_mode = :in_body
            anything_else_reprocess(token)
          end
        when CommentToken
          html = stack_of_open_elements.first_html("html")
          insert_comment(token, html || document)
        when DocTypeToken
          parse_error("unexpected-doctype")
        when StartTagToken
          if token.name == "html"
            process_in_body(token)
          else
            parse_error("unexpected-start-tag-after-body")
            @insertion_mode = :in_body
            anything_else_reprocess(token)
          end
        when EndTagToken
          if token.name == "html"
            if fragment? || stack_of_open_elements.include_html?("template")
              parse_error("unexpected-end-tag")
            else
              @insertion_mode = :after_after_body
            end
          else
            parse_error("unexpected-end-tag")
            @insertion_mode = :in_body
            anything_else_reprocess(token)
          end
        when EOFToken
          stop_parsing
        end
      end

      def process_after_after_body(token)
        case token
        when CommentToken
          insert_comment(token, document)
        when DocTypeToken, CharacterToken
          if token.is_a?(CharacterToken) && whitespace_character_token?(token)
            process_in_body(token)
          elsif token.is_a?(DocTypeToken)
            process_in_body(token)
          else
            parse_error("unexpected-token")
            @insertion_mode = :in_body
            anything_else_reprocess(token)
          end
        when StartTagToken
          if token.name == "html"
            process_in_body(token)
          else
            parse_error("unexpected-start-tag")
            @insertion_mode = :in_body
            anything_else_reprocess(token)
          end
        when EOFToken
          stop_parsing
        else
          parse_error("unexpected-token")
          @insertion_mode = :in_body
          anything_else_reprocess(token)
        end
      end

      # §13.2.6.4.18 The "in frameset" insertion mode
      def process_in_frameset(token)
        case token
        when CharacterToken
          if whitespace_character_token?(token)
            insert_character(token.value)
          else
            parse_error("unexpected-char-in-frameset")
          end
        when CommentToken
          insert_comment(token)
        when DocTypeToken
          parse_error("unexpected-doctype")
        when StartTagToken
          case token.name
          when "html"
            process_in_body(token)
          when "frameset"
            insert_html_element(token)
          when "frame"
            insert_html_element(token)
            stack_of_open_elements.pop
            acknowledge_self_closing_flag(token)
          when "noframes"
            process_in_head(token)
          else
            parse_error("unexpected-start-tag-in-frameset")
          end
        when EndTagToken
          if token.name == "frameset"
            if current_node&.html? && current_node.name == "html"
              parse_error("unexpected-end-tag")
            else
              stack_of_open_elements.pop
              still_frameset = current_node&.html? && current_node.name == "frameset"
              @insertion_mode = :after_frameset unless fragment? || still_frameset
            end
          else
            parse_error("unexpected-end-tag")
          end
        when EOFToken
          parse_error("eof-in-frameset") unless current_node&.html? && current_node.name == "html"
          stop_parsing
        end
      end

      # §13.2.6.4.19 The "after frameset" insertion mode
      def process_after_frameset(token)
        case token
        when CharacterToken
          if whitespace_character_token?(token)
            insert_character(token.value)
          else
            parse_error("unexpected-char-after-frameset")
          end
        when CommentToken
          insert_comment(token)
        when DocTypeToken
          parse_error("unexpected-doctype")
        when StartTagToken
          case token.name
          when "html"
            process_in_body(token)
          when "noframes"
            process_in_head(token)
          else
            parse_error("unexpected-start-tag")
          end
        when EndTagToken
          if token.name == "html"
            @insertion_mode = :after_after_frameset
          else
            parse_error("unexpected-end-tag")
          end
        when EOFToken
          stop_parsing
        end
      end

      # §13.2.6.4.21 The "after after frameset" insertion mode
      def process_after_after_frameset(token)
        case token
        when CommentToken
          insert_comment(token, document)
        when DocTypeToken
          process_in_body(token)
        when CharacterToken
          if whitespace_character_token?(token)
            process_in_body(token)
          else
            parse_error("unexpected-char")
          end
        when StartTagToken
          case token.name
          when "html"
            process_in_body(token)
          when "noframes"
            process_in_head(token)
          else
            parse_error("unexpected-start-tag")
          end
        when EndTagToken
          parse_error("unexpected-end-tag")
        when EOFToken
          stop_parsing
        end
      end

      # Legacy stubs — living standard folded select into "in body".
      def process_in_select(token)
        @insertion_mode = :in_body
        anything_else_reprocess(token)
      end

      def process_in_select_in_table(token)
        @insertion_mode = :in_body
        anything_else_reprocess(token)
      end

      def fragment_context_is?(name)
        fragment? && @context_element&.html? && @context_element.name == name
      end
    end
  end
end
