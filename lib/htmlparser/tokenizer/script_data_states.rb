# frozen_string_literal: true

module HTMLParser
  class Tokenizer
    # Tokenizer states for WHATWG HTML §13.2.5 script data (+ escape / double-escape).
    module ScriptDataStates
      # §13.2.5.4 Script data state
      def parse_script_data_state
        case consume_next_input_character
        when "<"
          # Switch to the script data less-than sign state.
          note_markup_start!
          switch_to(:script_data_less_than_sign)
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

      # §13.2.5.15 Script data less-than sign state
      def parse_script_data_less_than_sign_state
        case consume_next_input_character
        when "/"
          # Set the temporary buffer to the empty string. Switch to the script data end tag open state.
          @temporary_buffer = +""
          switch_to(:script_data_end_tag_open)
        when "!"
          # Switch to the script data escape start state. Emit a U+003C LESS-THAN SIGN character token and a U+0021 EXCLAMATION MARK character token.
          switch_to(:script_data_escape_start)
          emit(CharacterToken.new("<"))
          emit(CharacterToken.new("!"))
        else
          # Emit a U+003C LESS-THAN SIGN character token. Reconsume in the script data state.
          emit(CharacterToken.new("<"))
          reconsume(:script_data)
        end
      end

      # §13.2.5.16 Script data end tag open state
      def parse_script_data_end_tag_open_state
        case consume_next_input_character
        when /[a-z]/i
          # Create a new end tag token, set its tag name to the empty string. Reconsume in the script data end tag name state.
          @current_tag_token = new_end_tag_token
          reconsume(:script_data_end_tag_name)
        else
          # Emit a U+003C LESS-THAN SIGN character token and a U+002F SOLIDUS character token. Reconsume in the script data state.
          emit(CharacterToken.new("<"))
          emit(CharacterToken.new("/"))
          reconsume(:script_data)
        end
      end

      # §13.2.5.17 Script data end tag name state
      def parse_script_data_end_tag_name_state
        case consume_next_input_character
        when *WHITESPACE
          if appropriate_end_tag_token?
            switch_to(:before_attribute_name)
          else
            anything_else_in_script_data_end_tag_name
          end
        when "/"
          if appropriate_end_tag_token?
            switch_to(:self_closing_start_tag)
          else
            anything_else_in_script_data_end_tag_name
          end
        when ">"
          if appropriate_end_tag_token?
            switch_to_and_emit(:data, @current_tag_token)
          else
            anything_else_in_script_data_end_tag_name
          end
        when /[A-Z]/
          @current_tag_token.name << current_input_character.downcase
          @temporary_buffer << current_input_character
        when /[a-z]/
          @current_tag_token.name << current_input_character
          @temporary_buffer << current_input_character
        else
          anything_else_in_script_data_end_tag_name
        end
      end

      # §13.2.5.18 Script data escape start state
      def parse_script_data_escape_start_state
        case consume_next_input_character
        when "-"
          # Switch to the script data escape start dash state. Emit a U+002D HYPHEN-MINUS character token.
          switch_to(:script_data_escape_start_dash)
          emit(CharacterToken.new("-"))
        else
          # Reconsume in the script data state.
          reconsume(:script_data)
        end
      end

      # §13.2.5.19 Script data escape start dash state
      def parse_script_data_escape_start_dash_state
        case consume_next_input_character
        when "-"
          # Switch to the script data escaped dash dash state. Emit a U+002D HYPHEN-MINUS character token.
          switch_to(:script_data_escaped_dash_dash)
          emit(CharacterToken.new("-"))
        else
          # Reconsume in the script data state.
          reconsume(:script_data)
        end
      end

      # §13.2.5.20 Script data escaped state
      def parse_script_data_escaped_state
        case consume_next_input_character
        when "-"
          # Switch to the script data escaped dash state. Emit a U+002D HYPHEN-MINUS character token.
          switch_to(:script_data_escaped_dash)
          emit(CharacterToken.new("-"))
        when "<"
          # Switch to the script data escaped less-than sign state.
          note_markup_start!
          switch_to(:script_data_escaped_less_than_sign)
        when "\u0000"
          # This is an unexpected-null-character parse error. Emit a U+FFFD REPLACEMENT CHARACTER character token.
          parse_error("unexpected-null-character")
          emit(CharacterToken.new("\ufffd"))
        when EOF
          # This is an eof-in-script-html-comment-like-text parse error. Emit an end-of-file token.
          parse_error("eof-in-script-html-comment-like-text")
          emit_eof!
        else
          # Emit the current input character as a character token.
          emit(CharacterToken.new(current_input_character))
        end
      end

      # §13.2.5.21 Script data escaped dash state
      def parse_script_data_escaped_dash_state
        case consume_next_input_character
        when "-"
          # Switch to the script data escaped dash dash state. Emit a U+002D HYPHEN-MINUS character token.
          switch_to(:script_data_escaped_dash_dash)
          emit(CharacterToken.new("-"))
        when "<"
          # Switch to the script data escaped less-than sign state.
          note_markup_start!
          switch_to(:script_data_escaped_less_than_sign)
        when "\u0000"
          # This is an unexpected-null-character parse error. Switch to the script data escaped state. Emit a U+FFFD REPLACEMENT CHARACTER character token.
          parse_error("unexpected-null-character")
          switch_to(:script_data_escaped)
          emit(CharacterToken.new("\ufffd"))
        when EOF
          # This is an eof-in-script-html-comment-like-text parse error. Emit an end-of-file token.
          parse_error("eof-in-script-html-comment-like-text")
          emit_eof!
        else
          # Switch to the script data escaped state. Emit the current input character as a character token.
          switch_to(:script_data_escaped)
          emit(CharacterToken.new(current_input_character))
        end
      end

      # §13.2.5.22 Script data escaped dash dash state
      def parse_script_data_escaped_dash_dash_state
        case consume_next_input_character
        when "-"
          # Emit a U+002D HYPHEN-MINUS character token.
          emit(CharacterToken.new("-"))
        when "<"
          # Switch to the script data escaped less-than sign state.
          note_markup_start!
          switch_to(:script_data_escaped_less_than_sign)
        when ">"
          # Switch to the script data state. Emit a U+003E GREATER-THAN SIGN character token.
          switch_to(:script_data)
          emit(CharacterToken.new(">"))
        when "\u0000"
          # This is an unexpected-null-character parse error. Switch to the script data escaped state. Emit a U+FFFD REPLACEMENT CHARACTER character token.
          parse_error("unexpected-null-character")
          switch_to(:script_data_escaped)
          emit(CharacterToken.new("\ufffd"))
        when EOF
          # This is an eof-in-script-html-comment-like-text parse error. Emit an end-of-file token.
          parse_error("eof-in-script-html-comment-like-text")
          emit_eof!
        else
          # Switch to the script data escaped state. Emit the current input character as a character token.
          switch_to(:script_data_escaped)
          emit(CharacterToken.new(current_input_character))
        end
      end

      # §13.2.5.23 Script data escaped less-than sign state
      def parse_script_data_escaped_less_than_sign_state
        case consume_next_input_character
        when "/"
          # Set the temporary buffer to the empty string. Switch to the script data escaped end tag open state.
          @temporary_buffer = +""
          switch_to(:script_data_escaped_end_tag_open)
        when /[a-z]/i
          # Set the temporary buffer to the empty string. Emit a U+003C LESS-THAN SIGN character token. Reconsume in the script data double escape start state.
          @temporary_buffer = +""
          emit(CharacterToken.new("<"))
          reconsume(:script_data_double_escape_start)
        else
          # Emit a U+003C LESS-THAN SIGN character token. Reconsume in the script data escaped state.
          emit(CharacterToken.new("<"))
          reconsume(:script_data_escaped)
        end
      end

      # §13.2.5.24 Script data escaped end tag open state
      def parse_script_data_escaped_end_tag_open_state
        case consume_next_input_character
        when /[a-z]/i
          # Create a new end tag token, set its tag name to the empty string. Reconsume in the script data escaped end tag name state.
          @current_tag_token = new_end_tag_token
          reconsume(:script_data_escaped_end_tag_name)
        else
          # Emit a U+003C LESS-THAN SIGN character token and a U+002F SOLIDUS character token. Reconsume in the script data escaped state.
          emit(CharacterToken.new("<"))
          emit(CharacterToken.new("/"))
          reconsume(:script_data_escaped)
        end
      end

      # §13.2.5.25 Script data escaped end tag name state
      def parse_script_data_escaped_end_tag_name_state
        case consume_next_input_character
        when *WHITESPACE
          if appropriate_end_tag_token?
            switch_to(:before_attribute_name)
          else
            anything_else_in_script_data_escaped_end_tag_name
          end
        when "/"
          if appropriate_end_tag_token?
            switch_to(:self_closing_start_tag)
          else
            anything_else_in_script_data_escaped_end_tag_name
          end
        when ">"
          if appropriate_end_tag_token?
            switch_to_and_emit(:data, @current_tag_token)
          else
            anything_else_in_script_data_escaped_end_tag_name
          end
        when /[A-Z]/
          @current_tag_token.name << current_input_character.downcase
          @temporary_buffer << current_input_character
        when /[a-z]/
          @current_tag_token.name << current_input_character
          @temporary_buffer << current_input_character
        else
          anything_else_in_script_data_escaped_end_tag_name
        end
      end

      # §13.2.5.26 Script data double escape start state
      def parse_script_data_double_escape_start_state
        case consume_next_input_character
        when *WHITESPACE, "/", ">"
          # If the temporary buffer is "script", then switch to the script data double escaped state. Otherwise, switch to the script data escaped state. Emit the current input character as a character token.
          if @temporary_buffer == "script"
            switch_to(:script_data_double_escaped)
          else
            switch_to(:script_data_escaped)
          end
          emit(CharacterToken.new(current_input_character))
        when /[A-Z]/
          # Append the lowercase version of the current input character to the temporary buffer. Emit the current input character as a character token.
          @temporary_buffer << current_input_character.downcase
          emit(CharacterToken.new(current_input_character))
        when /[a-z]/
          # Append the current input character to the temporary buffer. Emit the current input character as a character token.
          @temporary_buffer << current_input_character
          emit(CharacterToken.new(current_input_character))
        else
          # Reconsume in the script data escaped state.
          reconsume(:script_data_escaped)
        end
      end

      # §13.2.5.27 Script data double escaped state
      def parse_script_data_double_escaped_state
        case consume_next_input_character
        when "-"
          # Switch to the script data double escaped dash state. Emit a U+002D HYPHEN-MINUS character token.
          switch_to(:script_data_double_escaped_dash)
          emit(CharacterToken.new("-"))
        when "<"
          # Switch to the script data double escaped less-than sign state. Emit a U+003C LESS-THAN SIGN character token.
          switch_to(:script_data_double_escaped_less_than_sign)
          emit(CharacterToken.new("<"))
        when "\u0000"
          # This is an unexpected-null-character parse error. Emit a U+FFFD REPLACEMENT CHARACTER character token.
          parse_error("unexpected-null-character")
          emit(CharacterToken.new("\ufffd"))
        when EOF
          # This is an eof-in-script-html-comment-like-text parse error. Emit an end-of-file token.
          parse_error("eof-in-script-html-comment-like-text")
          emit_eof!
        else
          # Emit the current input character as a character token.
          emit(CharacterToken.new(current_input_character))
        end
      end

      # §13.2.5.28 Script data double escaped dash state
      def parse_script_data_double_escaped_dash_state
        case consume_next_input_character
        when "-"
          # Switch to the script data double escaped dash dash state. Emit a U+002D HYPHEN-MINUS character token.
          switch_to(:script_data_double_escaped_dash_dash)
          emit(CharacterToken.new("-"))
        when "<"
          # Switch to the script data double escaped less-than sign state. Emit a U+003C LESS-THAN SIGN character token.
          switch_to(:script_data_double_escaped_less_than_sign)
          emit(CharacterToken.new("<"))
        when "\u0000"
          # This is an unexpected-null-character parse error. Switch to the script data double escaped state. Emit a U+FFFD REPLACEMENT CHARACTER character token.
          parse_error("unexpected-null-character")
          switch_to(:script_data_double_escaped)
          emit(CharacterToken.new("\ufffd"))
        when EOF
          # This is an eof-in-script-html-comment-like-text parse error. Emit an end-of-file token.
          parse_error("eof-in-script-html-comment-like-text")
          emit_eof!
        else
          # Switch to the script data double escaped state. Emit the current input character as a character token.
          switch_to(:script_data_double_escaped)
          emit(CharacterToken.new(current_input_character))
        end
      end

      # §13.2.5.29 Script data double escaped dash dash state
      def parse_script_data_double_escaped_dash_dash_state
        case consume_next_input_character
        when "-"
          # Emit a U+002D HYPHEN-MINUS character token.
          emit(CharacterToken.new("-"))
        when "<"
          # Switch to the script data double escaped less-than sign state. Emit a U+003C LESS-THAN SIGN character token.
          switch_to(:script_data_double_escaped_less_than_sign)
          emit(CharacterToken.new("<"))
        when ">"
          # Switch to the script data state. Emit a U+003E GREATER-THAN SIGN character token.
          switch_to(:script_data)
          emit(CharacterToken.new(">"))
        when "\u0000"
          # This is an unexpected-null-character parse error. Switch to the script data double escaped state. Emit a U+FFFD REPLACEMENT CHARACTER character token.
          parse_error("unexpected-null-character")
          switch_to(:script_data_double_escaped)
          emit(CharacterToken.new("\ufffd"))
        when EOF
          # This is an eof-in-script-html-comment-like-text parse error. Emit an end-of-file token.
          parse_error("eof-in-script-html-comment-like-text")
          emit_eof!
        else
          # Switch to the script data double escaped state. Emit the current input character as a character token.
          switch_to(:script_data_double_escaped)
          emit(CharacterToken.new(current_input_character))
        end
      end

      # §13.2.5.30 Script data double escaped less-than sign state
      def parse_script_data_double_escaped_less_than_sign_state
        case consume_next_input_character
        when "/"
          # Set the temporary buffer to the empty string. Switch to the script data double escape end state. Emit a U+002F SOLIDUS character token.
          @temporary_buffer = +""
          switch_to(:script_data_double_escape_end)
          emit(CharacterToken.new("/"))
        else
          # Reconsume in the script data double escaped state.
          reconsume(:script_data_double_escaped)
        end
      end

      # §13.2.5.31 Script data double escape end state
      def parse_script_data_double_escape_end_state
        case consume_next_input_character
        when *WHITESPACE, "/", ">"
          # If the temporary buffer is "script", then switch to the script data escaped state. Otherwise, switch to the script data double escaped state. Emit the current input character as a character token.
          if @temporary_buffer == "script"
            switch_to(:script_data_escaped)
          else
            switch_to(:script_data_double_escaped)
          end
          emit(CharacterToken.new(current_input_character))
        when /[A-Z]/
          # Append the lowercase version of the current input character to the temporary buffer. Emit the current input character as a character token.
          @temporary_buffer << current_input_character.downcase
          emit(CharacterToken.new(current_input_character))
        when /[a-z]/
          # Append the current input character to the temporary buffer. Emit the current input character as a character token.
          @temporary_buffer << current_input_character
          emit(CharacterToken.new(current_input_character))
        else
          # Reconsume in the script data double escaped state.
          reconsume(:script_data_double_escaped)
        end
      end

      private

      def anything_else_in_script_data_end_tag_name
        emit(CharacterToken.new("<"))
        emit(CharacterToken.new("/"))
        @temporary_buffer.each_char { |ch| emit(CharacterToken.new(ch.dup)) }
        reconsume(:script_data)
      end

      def anything_else_in_script_data_escaped_end_tag_name
        emit(CharacterToken.new("<"))
        emit(CharacterToken.new("/"))
        @temporary_buffer.each_char { |ch| emit(CharacterToken.new(ch.dup)) }
        reconsume(:script_data_escaped)
      end
    end
  end
end
