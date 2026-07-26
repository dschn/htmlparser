# frozen_string_literal: true

module HTMLParser
  class Tokenizer
    # Tokenizer states for WHATWG HTML §13.2.5 (see method comments).
    module DoctypeStates
      # §13.2.5.53 DOCTYPE state
      def parse_doctype_state
        case consume_next_input_character
        when *WHITESPACE
          # Switch to the before DOCTYPE name state.
          switch_to(:before_doctype_name)
        when ">"
          # Reconsume in the before DOCTYPE name state.
          reconsume(:before_doctype_name)
        when EOF
          # This is an eof-in-doctype parse error. Create a new DOCTYPE token. Set its force-quirks flag to on. Emit the current token. Emit an end-of-file token.
          new_doctype_token
          emit_eof_in_doctype!
        else
          # This is a missing-whitespace-before-doctype-name parse error. Reconsume in the before DOCTYPE name state.
          parse_error("missing-whitespace-before-doctype-name")
          reconsume(:before_doctype_name)
        end
      end

      # §13.2.5.54 Before DOCTYPE name state
      def parse_before_doctype_name_state
        case consume_next_input_character
        when *WHITESPACE
          # Ignore the character
        when /[A-Z]/
          # Create a new DOCTYPE token. Set the token's name to the lowercase version of the current input character (add 0x0020 to the character's code point). Switch to the DOCTYPE name state.
          new_doctype_token(+current_input_character.downcase)
          switch_to(:doctype_name)
        when "\u0000"
          # This is an unexpected-null-character parse error. Create a new DOCTYPE token. Set the token's name to a U+FFFD REPLACEMENT CHARACTER character. Switch to the DOCTYPE name state.
          parse_error("unexpected-null-character")
          new_doctype_token(+"\ufffd")
          switch_to(:doctype_name)
        when ">"
          # This is a missing-doctype-name parse error. Create a new DOCTYPE token. Set its force-quirks flag to on. Switch to the data state. Emit the current token.
          parse_error("missing-doctype-name")
          new_doctype_token
          @current_tag_token.force_quirks = true
          switch_to_and_emit(:data, @current_tag_token)
        when EOF
          # This is an eof-in-doctype parse error. Create a new DOCTYPE token. Set its force-quirks flag to on. Emit the current token. Emit an end-of-file token.
          new_doctype_token
          emit_eof_in_doctype!
        else
          # Create a new DOCTYPE token. Set the token's name to the current input character. Switch to the DOCTYPE name state.
          new_doctype_token(+current_input_character)
          switch_to(:doctype_name)
        end
      end

      # §13.2.5.55 DOCTYPE name state
      def parse_doctype_name_state
        case consume_next_input_character
        when *WHITESPACE
          # Switch to the after DOCTYPE name state.
          switch_to(:after_doctype_name)
        when ">"
          # Switch to the data state. Emit the current DOCTYPE token.
          switch_to_and_emit(:data, @current_tag_token)
        when /[A-Z]/
          # Append the lowercase version of the current input character (add 0x0020 to the character's code point) to the current DOCTYPE token's name.
          @current_tag_token.name << current_input_character.downcase
        when "\u0000"
          # This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current DOCTYPE token's name.
          parse_error("unexpected-null-character")
          @current_tag_token.name << "\ufffd"
        when EOF
          # This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
          emit_eof_in_doctype!
        else
          @current_tag_token.name << current_input_character
        end
      end

      # §13.2.5.56 After DOCTYPE name state
      def parse_after_doctype_name_state
        case consume_next_input_character
        when *WHITESPACE
          # Ignore the character.
        when ">"
          # Switch to the data state. Emit the current DOCTYPE token.
          switch_to_and_emit(:data, @current_tag_token)
        when EOF
          # This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
          emit_eof_in_doctype!
        else
          # If the six characters starting from the current input character are an ASCII case-insensitive match for the word "PUBLIC", then consume those characters and switch to the after DOCTYPE public keyword state.
          # Otherwise, if the six characters starting from the current input character are an ASCII case-insensitive match for the word "SYSTEM", then consume those characters and switch to the after DOCTYPE system keyword state.
          # Otherwise, this is an invalid-character-sequence-after-doctype-name parse error. Set the current DOCTYPE token's force-quirks flag to on. Reconsume in the bogus DOCTYPE state.
          if match_from_current?("PUBLIC")
            consume_keyword_rest("PUBLIC")
            switch_to(:after_doctype_public_keyword)
          elsif match_from_current?("SYSTEM")
            consume_keyword_rest("SYSTEM")
            switch_to(:after_doctype_system_keyword)
          else
            parse_error("invalid-character-sequence-after-doctype-name")
            @current_tag_token.force_quirks = true
            reconsume(:bogus_doctype)
          end
        end
      end

      # §13.2.5.57 After DOCTYPE public keyword state
      def parse_after_doctype_public_keyword_state
        case consume_next_input_character
        when *WHITESPACE
          # Switch to the before DOCTYPE public identifier state.
          switch_to(:before_doctype_public_identifier)
        when '"'
          # This is a missing-whitespace-after-doctype-public-keyword parse error. Set the current DOCTYPE token's public identifier to the empty string (not missing), then switch to the DOCTYPE public identifier (double-quoted) state.
          parse_error("missing-whitespace-after-doctype-public-keyword")
          @current_tag_token.public_identifier = +""
          switch_to(:doctype_public_identifier_double_quoted)
        when "'"
          # This is a missing-whitespace-after-doctype-public-keyword parse error. Set the current DOCTYPE token's public identifier to the empty string (not missing), then switch to the DOCTYPE public identifier (single-quoted) state.
          parse_error("missing-whitespace-after-doctype-public-keyword")
          @current_tag_token.public_identifier = +""
          switch_to(:doctype_public_identifier_single_quoted)
        when ">"
          # This is a missing-doctype-public-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Switch to the data state. Emit the current DOCTYPE token.
          parse_error("missing-doctype-public-identifier")
          @current_tag_token.force_quirks = true
          switch_to_and_emit(:data, @current_tag_token)
        when EOF
          # This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
          emit_eof_in_doctype!
        else
          # This is a missing-quote-before-doctype-public-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Reconsume in the bogus DOCTYPE state.
          parse_error("missing-quote-before-doctype-public-identifier")
          @current_tag_token.force_quirks = true
          reconsume(:bogus_doctype)
        end
      end

      # §13.2.5.58 Before DOCTYPE public identifier state
      def parse_before_doctype_public_identifier_state
        case consume_next_input_character
        when *WHITESPACE
          # Ignore the character.
        when '"'
          # Set the current DOCTYPE token's public identifier to the empty string (not missing), then switch to the DOCTYPE public identifier (double-quoted) state.
          @current_tag_token.public_identifier = +""
          switch_to(:doctype_public_identifier_double_quoted)
        when "'"
          # Set the current DOCTYPE token's public identifier to the empty string (not missing), then switch to the DOCTYPE public identifier (single-quoted) state.
          @current_tag_token.public_identifier = +""
          switch_to(:doctype_public_identifier_single_quoted)
        when ">"
          # This is a missing-doctype-public-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Switch to the data state. Emit the current DOCTYPE token.
          parse_error("missing-doctype-public-identifier")
          @current_tag_token.force_quirks = true
          switch_to_and_emit(:data, @current_tag_token)
        when EOF
          # This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
          emit_eof_in_doctype!
        else
          # This is a missing-quote-before-doctype-public-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Reconsume in the bogus DOCTYPE state.
          parse_error("missing-quote-before-doctype-public-identifier")
          @current_tag_token.force_quirks = true
          reconsume(:bogus_doctype)
        end
      end

      # §13.2.5.59 DOCTYPE public identifier (double-quoted) state
      def parse_doctype_public_identifier_double_quoted_state
        case consume_next_input_character
        when '"'
          # Switch to the after DOCTYPE public identifier state.
          switch_to(:after_doctype_public_identifier)
        when "\u0000"
          # This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current DOCTYPE token's public identifier.
          parse_error("unexpected-null-character")
          @current_tag_token.public_identifier << "\ufffd"
        when ">"
          # This is an abrupt-doctype-public-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Switch to the data state. Emit the current DOCTYPE token.
          parse_error("abrupt-doctype-public-identifier")
          @current_tag_token.force_quirks = true
          switch_to_and_emit(:data, @current_tag_token)
        when EOF
          # This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
          emit_eof_in_doctype!
        else
          # Append the current input character to the current DOCTYPE token's public identifier.
          @current_tag_token.public_identifier << current_input_character
        end
      end

      # §13.2.5.60 DOCTYPE public identifier (single-quoted) state
      def parse_doctype_public_identifier_single_quoted_state
        case consume_next_input_character
        when "'"
          # Switch to the after DOCTYPE public identifier state.
          switch_to(:after_doctype_public_identifier)
        when "\u0000"
          # This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current DOCTYPE token's public identifier.
          parse_error("unexpected-null-character")
          @current_tag_token.public_identifier << "\ufffd"
        when ">"
          # This is an abrupt-doctype-public-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Switch to the data state. Emit the current DOCTYPE token.
          parse_error("abrupt-doctype-public-identifier")
          @current_tag_token.force_quirks = true
          switch_to_and_emit(:data, @current_tag_token)
        when EOF
          # This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
          emit_eof_in_doctype!
        else
          # Append the current input character to the current DOCTYPE token's public identifier.
          @current_tag_token.public_identifier << current_input_character
        end
      end

      # §13.2.5.61 After DOCTYPE public identifier state
      def parse_after_doctype_public_identifier_state
        case consume_next_input_character
        when *WHITESPACE
          # Switch to the between DOCTYPE public and system identifiers state.
          switch_to(:between_doctype_public_and_system_identifiers)
        when ">"
          # Switch to the data state. Emit the current DOCTYPE token.
          switch_to_and_emit(:data, @current_tag_token)
        when '"'
          # This is a missing-whitespace-between-doctype-public-and-system-identifiers parse error. Set the current DOCTYPE token's system identifier to the empty string (not missing), then switch to the DOCTYPE system identifier (double-quoted) state.
          parse_error("missing-whitespace-between-doctype-public-and-system-identifiers")
          @current_tag_token.system_identifier = +""
          switch_to(:doctype_system_identifier_double_quoted)
        when "'"
          # This is a missing-whitespace-between-doctype-public-and-system-identifiers parse error. Set the current DOCTYPE token's system identifier to the empty string (not missing), then switch to the DOCTYPE system identifier (single-quoted) state.
          parse_error("missing-whitespace-between-doctype-public-and-system-identifiers")
          @current_tag_token.system_identifier = +""
          switch_to(:doctype_system_identifier_single_quoted)
        when EOF
          # This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
          emit_eof_in_doctype!
        else
          # This is a missing-quote-before-doctype-system-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Reconsume in the bogus DOCTYPE state.
          parse_error("missing-quote-before-doctype-system-identifier")
          @current_tag_token.force_quirks = true
          reconsume(:bogus_doctype)
        end
      end

      # §13.2.5.62 Between DOCTYPE public and system identifiers state
      def parse_between_doctype_public_and_system_identifiers_state
        case consume_next_input_character
        when *WHITESPACE
          # Ignore the character.
        when ">"
          # Switch to the data state. Emit the current DOCTYPE token.
          switch_to_and_emit(:data, @current_tag_token)
        when '"'
          # Set the current DOCTYPE token's system identifier to the empty string (not missing), then switch to the DOCTYPE system identifier (double-quoted) state.
          @current_tag_token.system_identifier = +""
          switch_to(:doctype_system_identifier_double_quoted)
        when "'"
          # Set the current DOCTYPE token's system identifier to the empty string (not missing), then switch to the DOCTYPE system identifier (single-quoted) state.
          @current_tag_token.system_identifier = +""
          switch_to(:doctype_system_identifier_single_quoted)
        when EOF
          # This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
          emit_eof_in_doctype!
        else
          # This is a missing-quote-before-doctype-system-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Reconsume in the bogus DOCTYPE state.
          parse_error("missing-quote-before-doctype-system-identifier")
          @current_tag_token.force_quirks = true
          reconsume(:bogus_doctype)
        end
      end

      # §13.2.5.63 After DOCTYPE system keyword state
      def parse_after_doctype_system_keyword_state
        case consume_next_input_character
        when *WHITESPACE
          # Switch to the before DOCTYPE system identifier state.
          switch_to(:before_doctype_system_identifier)
        when '"'
          # This is a missing-whitespace-after-doctype-system-keyword parse error. Set the current DOCTYPE token's system identifier to the empty string (not missing), then switch to the DOCTYPE system identifier (double-quoted) state.
          parse_error("missing-whitespace-after-doctype-system-keyword")
          @current_tag_token.system_identifier = +""
          switch_to(:doctype_system_identifier_double_quoted)
        when "'"
          # This is a missing-whitespace-after-doctype-system-keyword parse error. Set the current DOCTYPE token's system identifier to the empty string (not missing), then switch to the DOCTYPE system identifier (single-quoted) state.
          parse_error("missing-whitespace-after-doctype-system-keyword")
          @current_tag_token.system_identifier = +""
          switch_to(:doctype_system_identifier_single_quoted)
        when ">"
          # This is a missing-doctype-system-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Switch to the data state. Emit the current DOCTYPE token.
          parse_error("missing-doctype-system-identifier")
          @current_tag_token.force_quirks = true
          switch_to_and_emit(:data, @current_tag_token)
        when EOF
          # This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
          emit_eof_in_doctype!
        else
          # This is a missing-quote-before-doctype-system-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Reconsume in the bogus DOCTYPE state.
          parse_error("missing-quote-before-doctype-system-identifier")
          @current_tag_token.force_quirks = true
          reconsume(:bogus_doctype)
        end
      end

      # §13.2.5.64 Before DOCTYPE system identifier state
      def parse_before_doctype_system_identifier_state
        case consume_next_input_character
        when *WHITESPACE
          # Ignore the character.
        when '"'
          # Set the current DOCTYPE token's system identifier to the empty string (not missing), then switch to the DOCTYPE system identifier (double-quoted) state.
          @current_tag_token.system_identifier = +""
          switch_to(:doctype_system_identifier_double_quoted)
        when "'"
          # Set the current DOCTYPE token's system identifier to the empty string (not missing), then switch to the DOCTYPE system identifier (single-quoted) state.
          @current_tag_token.system_identifier = +""
          switch_to(:doctype_system_identifier_single_quoted)
        when ">"
          # This is a missing-doctype-system-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Switch to the data state. Emit the current DOCTYPE token.
          parse_error("missing-doctype-system-identifier")
          @current_tag_token.force_quirks = true
          switch_to_and_emit(:data, @current_tag_token)
        when EOF
          # This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
          emit_eof_in_doctype!
        else
          # This is a missing-quote-before-doctype-system-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Reconsume in the bogus DOCTYPE state.
          parse_error("missing-quote-before-doctype-system-identifier")
          @current_tag_token.force_quirks = true
          reconsume(:bogus_doctype)
        end
      end

      # §13.2.5.65 DOCTYPE system identifier (double-quoted) state
      def parse_doctype_system_identifier_double_quoted_state
        case consume_next_input_character
        when '"'
          # Switch to the after DOCTYPE system identifier state.
          switch_to(:after_doctype_system_identifier)
        when "\u0000"
          # This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current DOCTYPE token's system identifier.
          parse_error("unexpected-null-character")
          @current_tag_token.system_identifier << "\ufffd"
        when ">"
          # This is an abrupt-doctype-system-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Switch to the data state. Emit the current DOCTYPE token.
          parse_error("abrupt-doctype-system-identifier")
          @current_tag_token.force_quirks = true
          switch_to_and_emit(:data, @current_tag_token)
        when EOF
          # This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
          emit_eof_in_doctype!
        else
          # Append the current input character to the current DOCTYPE token's system identifier.
          @current_tag_token.system_identifier << current_input_character
        end
      end

      # §13.2.5.66 DOCTYPE system identifier (single-quoted) state
      def parse_doctype_system_identifier_single_quoted_state
        case consume_next_input_character
        when "'"
          # Switch to the after DOCTYPE system identifier state.
          switch_to(:after_doctype_system_identifier)
        when "\u0000"
          # This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current DOCTYPE token's system identifier.
          parse_error("unexpected-null-character")
          @current_tag_token.system_identifier << "\ufffd"
        when ">"
          # This is an abrupt-doctype-system-identifier parse error. Set the current DOCTYPE token's force-quirks flag to on. Switch to the data state. Emit the current DOCTYPE token.
          parse_error("abrupt-doctype-system-identifier")
          @current_tag_token.force_quirks = true
          switch_to_and_emit(:data, @current_tag_token)
        when EOF
          # This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
          emit_eof_in_doctype!
        else
          # Append the current input character to the current DOCTYPE token's system identifier.
          @current_tag_token.system_identifier << current_input_character
        end
      end

      # §13.2.5.67 After DOCTYPE system identifier state
      def parse_after_doctype_system_identifier_state
        case consume_next_input_character
        when *WHITESPACE
          # Ignore the character.
        when ">"
          # Switch to the data state. Emit the current DOCTYPE token.
          switch_to_and_emit(:data, @current_tag_token)
        when EOF
          # This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
          emit_eof_in_doctype!
        else
          # This is an unexpected-character-after-doctype-system-identifier parse error. Reconsume in the bogus DOCTYPE state. (This does not set the current DOCTYPE token's force-quirks flag to on.)
          parse_error("unexpected-character-after-doctype-system-identifier")
          reconsume(:bogus_doctype)
        end
      end

      # §13.2.5.68 Bogus DOCTYPE state
      def parse_bogus_doctype_state
        case consume_next_input_character
        when ">"
          # Switch to the data state. Emit the current DOCTYPE token.
          switch_to_and_emit(:data, @current_tag_token)
        when "\u0000"
          # This is an unexpected-null-character parse error. Ignore the character.
          parse_error("unexpected-null-character")
        when EOF
          # Emit the current DOCTYPE token. Emit an end-of-file token.
          emit(@current_tag_token)
          emit_eof!
        else
          # Ignore the character.
        end
      end
    end
  end
end
