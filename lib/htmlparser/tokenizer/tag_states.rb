# frozen_string_literal: true

module HTMLParser
  class Tokenizer
    # Tokenizer states for WHATWG HTML §13.2.5 (see method comments).
    module TagStates
      # §13.2.5.1 Data state
      def parse_data_state
        case consume_next_input_character
        when "&"
          # Set the return state to the data state. Switch to the character reference state.
          flush_character_buffer!
          return_to_and_switch_to(:data, :character_reference)
        when "<"
          # Switch to the tag open state.
          flush_character_buffer!
          note_markup_start!
          switch_to(:tag_open)
        when "\u0000"
          # This is an unexpected-null-character parse error. Emit the current input character as a character token.
          flush_character_buffer!
          parse_error("unexpected-null-character")
          emit(CharacterToken.new(current_input_character))
        when EOF
          # Emit an end-of-file token.
          flush_character_buffer!
          emit_eof!
        when *WHITESPACE
          # Keep whitespace as one-char tokens (frameset / ignore-LF / colgroup).
          flush_character_buffer!
          emit(CharacterToken.new(current_input_character))
        else
          # Buffer non-whitespace runs (html5lib-style) so tree `#errors` like
          # expected-doctype-but-got-chars land at the end of the run.
          append_to_character_buffer(current_input_character)
        end
      end

      # §13.2.5.6 Tag open state
      def parse_tag_open_state
        case consume_next_input_character
        when "!"
          # Switch to the markup declaration open state.
          switch_to(:markup_declaration_open)
        when "/"
          # Switch to the end tag open state.
          switch_to(:end_tag_open)
        when /[a-z]/i # ASCII alpha
          # Create a new start tag token, set its tag name to the empty string. Reconsume in the tag name state.
          @current_tag_token = new_start_tag_token
          reconsume(:tag_name)
        when "?"
          # This is an unexpected-question-mark-instead-of-tag-name parse error. Create a comment token whose data is the empty string. Reconsume in the bogus comment state.
          parse_error("unexpected-question-mark-instead-of-tag-name")
          @comment_token = new_comment_token
          reconsume(:bogus_comment)
        when EOF
          # This is an eof-before-tag-name parse error. Emit a U+003C LESS-THAN SIGN character token and an end-of-file token.
          parse_error("eof-before-tag-name")
          emit(CharacterToken.new("\u003c"))
          emit_eof!
        else
          # This is an invalid-first-character-of-tag-name parse error. Emit a U+003C LESS-THAN SIGN character token. Reconsume in the data state.
          parse_error("invalid-first-character-of-tag-name")
          emit(CharacterToken.new("\u003c"))
          reconsume(:data)
        end
      end

      # §13.2.5.7 End tag open state
      def parse_end_tag_open_state
        case consume_next_input_character
        when /[a-z]/i
          # Create a new end tag token, set its tag name to the empty string. Reconsume in the tag name state.
          @current_tag_token = new_end_tag_token
          reconsume(:tag_name)
        when ">"
          # This is a missing-end-tag-name parse error. Switch to the data state.
          parse_error("missing-end-tag-name")
          switch_to(:data)
        when EOF
          # This is an eof-before-tag-name parse error. Emit a U+003C LESS-THAN SIGN character token, a U+002F SOLIDUS character token and an end-of-file token.
          parse_error("eof-before-tag-name")
          emit(CharacterToken.new("\u003c"))
          emit(CharacterToken.new("\u002f"))
          emit_eof!
        else
          # This is an invalid-first-character-of-tag-name parse error. Create a comment token whose data is the empty string. Reconsume in the bogus comment state.
          parse_error("invalid-first-character-of-tag-name")
          @comment_token = new_comment_token
          reconsume(:bogus_comment)
        end
      end

      # §13.2.5.8 Tag name state
      def parse_tag_name_state
        case consume_next_input_character
        when *WHITESPACE
          # Switch to the before attribute name state.
          switch_to(:before_attribute_name)
        when "/"
          # Switch to the self-closing start tag state.
          switch_to(:self_closing_start_tag)
        when ">"
          # Switch to the data state. Emit the current tag token.
          switch_to(:data)
          emit(@current_tag_token)
        when /[A-Z]/
          # Append the lowercase version of the current input character (add 0x0020 to the character's code point) to the current tag token's tag name.
          @current_tag_token.name << current_input_character.downcase
        when "\u0000" # U+0000 NULL
          # This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current tag token's tag name.
          parse_error("unexpected-null-character")
          @current_tag_token.name << "\ufffd"
        when EOF
          # This is an eof-in-tag parse error. Emit an end-of-file token.
          emit_eof_in_tag!
        else
          # Append the current input character to the current tag token's tag name.
          @current_tag_token.name << current_input_character
        end
      end

      # §13.2.5.32 Before attribute name state
      def parse_before_attribute_name_state
        case consume_next_input_character
        when *WHITESPACE
          # Ignore the character.
        when "/", ">", EOF
          # Reconsume in the after attribute name state.
          reconsume(:after_attribute_name)
        when "="
          # This is an unexpected-equals-sign-before-attribute-name parse error. Start a new attribute in the current tag token. Set that attribute's name to the current input character, and its value to the empty string. Switch to the attribute name state.
          parse_error("unexpected-equals-sign-before-attribute-name")
          @discard_attribute_value = false
          @current_tag_token.attributes << {name: current_input_character.dup, value: +""}
          switch_to(:attribute_name)
        else
          # Start a new attribute in the current tag token. Set that attribute name and value to the empty string. Reconsume in the attribute name state.
          @discard_attribute_value = false
          @current_tag_token.attributes << {name: +"", value: +""}
          reconsume(:attribute_name)
        end
      end

      # §13.2.5.33 Attribute name state
      def parse_attribute_name_state
        case consume_next_input_character
        when *WHITESPACE, "\u002f", "\u003e", EOF
          # Reconsume in the after attribute name state.
          # When leaving attribute name state: duplicate-attribute check (§13.2.5.33).
          drop_duplicate_attribute_if_needed!
          reconsume(:after_attribute_name)
        when "="
          # Switch to the before attribute value state.
          drop_duplicate_attribute_if_needed!
          switch_to(:before_attribute_value)
        when /[A-Z]/
          # Append the lowercase version of the current input character (add 0x0020 to the character's code point) to the current attribute's name.
          @current_tag_token.attributes.last[:name] << current_input_character.downcase
        when "\u0000"
          # This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current attribute's name.
          append_replacement_to_attribute_name!
        # U+0022 QUOTATION MARK (")
        # U+0027 APOSTROPHE (')
        # U+003C LESS-THAN SIGN (<)
        when "\u0022", "\u0027", "\u003c"
          # This is an unexpected-character-in-attribute-name parse error. Treat it as per the "anything else" entry below.
          parse_error("unexpected-character-in-attribute-name")
          @current_tag_token.attributes.last[:name] << current_input_character
        else
          # Append the current input character to the current attribute's name.
          @current_tag_token.attributes.last[:name] << current_input_character
        end
      end

      # When the user agent leaves the attribute name state, compare the complete
      # attribute's name to other attributes on the token; on a match, this is a
      # duplicate-attribute parse error and the new attribute must be removed.
      # Subsequent value characters are discarded (@discard_attribute_value).
      def drop_duplicate_attribute_if_needed!
        attrs = @current_tag_token.attributes
        name = attrs.last[:name]
        if attrs[0...-1].any? { |attr| attr[:name] == name }
          parse_error("duplicate-attribute")
          attrs.pop
          @discard_attribute_value = true
        else
          @discard_attribute_value = false
        end
      end

      # §13.2.5.34 After attribute name state
      def parse_after_attribute_name_state
        case consume_next_input_character
        when *WHITESPACE
          # Ignore the character.
        when "/"
          # Switch to the self-closing start tag state.
          switch_to(:self_closing_start_tag)
        when "="
          # Switch to the before attribute value state.
          switch_to(:before_attribute_value)
        when ">"
          # Switch to the data state. Emit the current tag token.
          switch_to_and_emit(:data, @current_tag_token)
        when EOF
          # This is an eof-in-tag parse error. Emit an end-of-file token.
          emit_eof_in_tag!
        else
          # Start a new attribute in the current tag token. Set that attribute name and value to the empty string. Reconsume in the attribute name state.
          @discard_attribute_value = false
          @current_tag_token.attributes << {name: +"", value: +""}
          reconsume(:attribute_name)
        end
      end

      # §13.2.5.35 Before attribute value state
      def parse_before_attribute_value_state
        case consume_next_input_character
        when *WHITESPACE
          # Ignore the character.
        when '"'
          # Switch to the attribute value (double-quoted) state.
          switch_to(:attribute_value_double_quoted)
        when "'"
          # Switch to the attribute value (single-quoted) state.
          switch_to(:attribute_value_single_quoted)
        when ">"
          # This is a missing-attribute-value parse error. Switch to the data state. Emit the current tag token.
          parse_error("missing-attribute-value")
          switch_to(:data)
          emit(@current_tag_token)
        else
          # Reconsume in the attribute value (unquoted) state.
          reconsume(:attribute_value_unquoted)
        end
      end

      # §13.2.5.36 Attribute value (double-quoted) state
      def parse_attribute_value_double_quoted_state
        case consume_next_input_character
        when '"'
          # Switch to the after attribute value (quoted) state.
          switch_to(:after_attribute_value_quoted)
        when "&"
          # Set the return state to the attribute value (double-quoted) state. Switch to the character reference state.
          return_to_and_switch_to(:attribute_value_double_quoted, :character_reference)
        when "\u0000"
          # This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current attribute's value.
          append_replacement_to_attribute_value!
        when EOF
          # This is an eof-in-tag parse error. Emit an end-of-file token.
          emit_eof_in_tag!
        else
          # Append the current input character to the current attribute's value.
          append_to_current_attribute_value!(current_input_character)
        end
      end

      # §13.2.5.37 Attribute value (single-quoted) state
      def parse_attribute_value_single_quoted_state
        case consume_next_input_character
        when "'"
          # Switch to the after attribute value (quoted) state.
          switch_to(:after_attribute_value_quoted)
        when "&"
          # Set the return state to the attribute value (single-quoted) state. Switch to the character reference state.
          return_to_and_switch_to(:attribute_value_single_quoted, :character_reference)
        when "\u0000"
          # This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current attribute's value.
          append_replacement_to_attribute_value!
        when EOF
          # This is an eof-in-tag parse error. Emit an end-of-file token.
          emit_eof_in_tag!
        else
          # Append the current input character to the current attribute's value.
          append_to_current_attribute_value!(current_input_character)
        end
      end

      # §13.2.5.38 Attribute value (unquoted) state
      def parse_attribute_value_unquoted_state
        case consume_next_input_character
        when *WHITESPACE
          # Switch to the before attribute name state.
          switch_to(:before_attribute_name)
        when "&"
          # Set the return state to the attribute value (unquoted) state. Switch to the character reference state.
          return_to_and_switch_to(:attribute_value_unquoted, :character_reference)
        when ">"
          # Switch to the data state. Emit the current tag token.
          switch_to_and_emit(:data, @current_tag_token)
        when "\u0000"
          # This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current attribute's value.
          append_replacement_to_attribute_value!
        when '"', "'", "<", "=", "`"
          # This is an unexpected-character-in-unquoted-attribute-value parse error. Treat it as per the "anything else" entry below.
          parse_error("unexpected-character-in-unquoted-attribute-value")
          append_to_current_attribute_value!(current_input_character)
        when EOF
          # This is an eof-in-tag parse error. Emit an end-of-file token.
          emit_eof_in_tag!
        else
          # Append the current input character to the current attribute's value.
          append_to_current_attribute_value!(current_input_character)
        end
      end

      # §13.2.5.39 After attribute value (quoted) state
      def parse_after_attribute_value_quoted_state
        case consume_next_input_character
        when *WHITESPACE
          # Switch to the before attribute name state.
          switch_to(:before_attribute_name)
        when "/"
          # Switch to the self-closing start tag state.
          switch_to(:self_closing_start_tag)
        when ">"
          # Switch to the data state. Emit the current tag token.
          switch_to_and_emit(:data, @current_tag_token)
        when EOF
          # This is an eof-in-tag parse error. Emit an end-of-file token.
          emit_eof_in_tag!
        else
          # This is a missing-whitespace-between-attributes parse error. Reconsume in the before attribute name state.
          parse_error("missing-whitespace-between-attributes")
          reconsume(:before_attribute_name)
        end
      end

      # §13.2.5.40 Self-closing start tag state
      def parse_self_closing_start_tag_state
        case consume_next_input_character
        when ">"
          # Set the self-closing flag of the current tag token. Switch to the data state. Emit the current tag token.
          @current_tag_token.self_closing = true
          switch_to_and_emit(:data, @current_tag_token)
        when EOF
          # This is an eof-in-tag parse error. Emit an end-of-file token.
          emit_eof_in_tag!
        else
          # This is an unexpected-solidus-in-tag parse error. Reconsume in the before attribute name state.
          parse_error("unexpected-solidus-in-tag")
          reconsume(:before_attribute_name)
        end
      end
    end
  end
end
