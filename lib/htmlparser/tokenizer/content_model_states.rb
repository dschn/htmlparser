# frozen_string_literal: true

module HTMLParser
  class Tokenizer
    # Tokenizer states for WHATWG HTML §13.2.5 content models (RCDATA / RAWTEXT / PLAINTEXT).
    module ContentModelStates
      # §13.2.5.2 RCDATA state
      def parse_rcdata_state
        case consume_next_input_character
        when "&"
          # Set the return state to the RCDATA state. Switch to the character reference state.
          return_to_and_switch_to(:rcdata, :character_reference)
        when "<"
          # Switch to the RCDATA less-than sign state.
          switch_to(:rcdata_less_than_sign)
        when "\u0000"
          # This is an unexpected-null-character parse error. Emit a U+FFFD REPLACEMENT CHARACTER character token.
          parse_error("unexpected-null-character")
          emit(CharacterToken.new("\ufffd"))
        when EOF
          # Emit an end-of-file token.
          emit_eof!
        else
          # Emit the current input character as a character token.
          emit(CharacterToken.new(current_input_character))
        end
      end

      # §13.2.5.3 RAWTEXT state
      def parse_rawtext_state
        case consume_next_input_character
        when "<"
          # Switch to the RAWTEXT less-than sign state.
          switch_to(:rawtext_less_than_sign)
        when "\u0000"
          # This is an unexpected-null-character parse error. Emit a U+FFFD REPLACEMENT CHARACTER character token.
          parse_error("unexpected-null-character")
          emit(CharacterToken.new("\ufffd"))
        when EOF
          # Emit an end-of-file token.
          emit_eof!
        else
          # Emit the current input character as a character token.
          emit(CharacterToken.new(current_input_character))
        end
      end

      # §13.2.5.5 PLAINTEXT state
      def parse_plaintext_state
        case consume_next_input_character
        when "\u0000"
          # This is an unexpected-null-character parse error. Emit a U+FFFD REPLACEMENT CHARACTER character token.
          parse_error("unexpected-null-character")
          emit(CharacterToken.new("\ufffd"))
        when EOF
          # Emit an end-of-file token.
          emit_eof!
        else
          # Emit the current input character as a character token.
          emit(CharacterToken.new(current_input_character))
        end
      end

      # §13.2.5.9 RCDATA less-than sign state
      def parse_rcdata_less_than_sign_state
        case consume_next_input_character
        when "/"
          # Set the temporary buffer to the empty string. Switch to the RCDATA end tag open state.
          @temporary_buffer = +""
          switch_to(:rcdata_end_tag_open)
        else
          # Emit a U+003C LESS-THAN SIGN character token. Reconsume in the RCDATA state.
          emit(CharacterToken.new("<"))
          reconsume(:rcdata)
        end
      end

      # §13.2.5.10 RCDATA end tag open state
      def parse_rcdata_end_tag_open_state
        case consume_next_input_character
        when /[a-z]/i
          # Create a new end tag token, set its tag name to the empty string. Reconsume in the RCDATA end tag name state.
          @current_tag_token = EndTagToken.new(+"")
          reconsume(:rcdata_end_tag_name)
        else
          # Emit a U+003C LESS-THAN SIGN character token and a U+002F SOLIDUS character token. Reconsume in the RCDATA state.
          emit(CharacterToken.new("<"))
          emit(CharacterToken.new("/"))
          reconsume(:rcdata)
        end
      end

      # §13.2.5.11 RCDATA end tag name state
      def parse_rcdata_end_tag_name_state
        case consume_next_input_character
        when *WHITESPACE
          # If the current end tag token is an appropriate end tag token, then switch to the before attribute name state. Otherwise, treat it as per the "anything else" entry below.
          if appropriate_end_tag_token?
            switch_to(:before_attribute_name)
          else
            anything_else_in_rcdata_end_tag_name
          end
        when "/"
          # If the current end tag token is an appropriate end tag token, then switch to the self-closing start tag state. Otherwise, treat it as per the "anything else" entry below.
          if appropriate_end_tag_token?
            switch_to(:self_closing_start_tag)
          else
            anything_else_in_rcdata_end_tag_name
          end
        when ">"
          # If the current end tag token is an appropriate end tag token, then switch to the data state and emit the current tag token. Otherwise, treat it as per the "anything else" entry below.
          if appropriate_end_tag_token?
            switch_to_and_emit(:data, @current_tag_token)
          else
            anything_else_in_rcdata_end_tag_name
          end
        when /[A-Z]/
          # Append the lowercase version of the current input character to the current tag token's tag name. Append the current input character to the temporary buffer.
          @current_tag_token.name << current_input_character.downcase
          @temporary_buffer << current_input_character
        when /[a-z]/
          # Append the current input character to the current tag token's tag name. Append the current input character to the temporary buffer.
          @current_tag_token.name << current_input_character
          @temporary_buffer << current_input_character
        else
          anything_else_in_rcdata_end_tag_name
        end
      end

      # §13.2.5.12 RAWTEXT less-than sign state
      def parse_rawtext_less_than_sign_state
        case consume_next_input_character
        when "/"
          # Set the temporary buffer to the empty string. Switch to the RAWTEXT end tag open state.
          @temporary_buffer = +""
          switch_to(:rawtext_end_tag_open)
        else
          # Emit a U+003C LESS-THAN SIGN character token. Reconsume in the RAWTEXT state.
          emit(CharacterToken.new("<"))
          reconsume(:rawtext)
        end
      end

      # §13.2.5.13 RAWTEXT end tag open state
      def parse_rawtext_end_tag_open_state
        case consume_next_input_character
        when /[a-z]/i
          # Create a new end tag token, set its tag name to the empty string. Reconsume in the RAWTEXT end tag name state.
          @current_tag_token = EndTagToken.new(+"")
          reconsume(:rawtext_end_tag_name)
        else
          # Emit a U+003C LESS-THAN SIGN character token and a U+002F SOLIDUS character token. Reconsume in the RAWTEXT state.
          emit(CharacterToken.new("<"))
          emit(CharacterToken.new("/"))
          reconsume(:rawtext)
        end
      end

      # §13.2.5.14 RAWTEXT end tag name state
      def parse_rawtext_end_tag_name_state
        case consume_next_input_character
        when *WHITESPACE
          if appropriate_end_tag_token?
            switch_to(:before_attribute_name)
          else
            anything_else_in_rawtext_end_tag_name
          end
        when "/"
          if appropriate_end_tag_token?
            switch_to(:self_closing_start_tag)
          else
            anything_else_in_rawtext_end_tag_name
          end
        when ">"
          if appropriate_end_tag_token?
            switch_to_and_emit(:data, @current_tag_token)
          else
            anything_else_in_rawtext_end_tag_name
          end
        when /[A-Z]/
          @current_tag_token.name << current_input_character.downcase
          @temporary_buffer << current_input_character
        when /[a-z]/
          @current_tag_token.name << current_input_character
          @temporary_buffer << current_input_character
        else
          anything_else_in_rawtext_end_tag_name
        end
      end

      private

      # Emit "</" + temporary buffer as characters, then reconsume in RCDATA.
      def anything_else_in_rcdata_end_tag_name
        emit(CharacterToken.new("<"))
        emit(CharacterToken.new("/"))
        @temporary_buffer.each_char { |ch| emit(CharacterToken.new(ch.dup)) }
        reconsume(:rcdata)
      end

      # Emit "</" + temporary buffer as characters, then reconsume in RAWTEXT.
      def anything_else_in_rawtext_end_tag_name
        emit(CharacterToken.new("<"))
        emit(CharacterToken.new("/"))
        @temporary_buffer.each_char { |ch| emit(CharacterToken.new(ch.dup)) }
        reconsume(:rawtext)
      end
    end
  end
end
