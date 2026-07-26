# frozen_string_literal: true

module HTMLParser
  class Tokenizer
    # Tokenizer states for WHATWG HTML §13.2.5 (see method comments).
    module CharacterReferenceStates
      # §13.2.5.72 Character reference state
      def parse_character_reference_state
        # Set the temporary buffer to the empty string. Append a U+0026 AMPERSAND (&) character to the temporary buffer. Consume the next input character:
        @temporary_buffer = +"&"

        case consume_next_input_character
        when /[a-z0-9]/i
          # Reconsume in the named character reference state.
          reconsume(:named_character_reference)
        when "#"
          # Append the current input character to the temporary buffer. Switch to the numeric character reference state.
          @temporary_buffer << current_input_character
          switch_to(:numeric_character_reference)
        else
          # Flush code points consumed as a character reference. Reconsume in the return state.
          flush_code_points_consumed_as_character_reference
          reconsume(@return_state)
        end
      end

      # §13.2.5.73 Named character reference state
      def parse_named_character_reference_state
        # Match from the current input character (already consumed; stream pos is after it).
        substring = @input_stream.string_from(@input_stream.pos - 1)
        match = ENTITIES_KEYS.select { |name| substring.start_with?(name) }.max_by(&:length)

        if match
          @input_stream.pos += (match.size - 1)

          # Historical: in an attribute, if the match has no trailing semicolon and
          # the next character is '=' or an ASCII alphanumeric, treat as a failed
          # match (flush "&" + matched name literally). Full fidelity TBD with html5lib.
          if consumed_as_part_of_an_attribute? && !match.end_with?(";")
            next_character = @input_stream.peek(1)
            if next_character && (next_character == "=" || next_character.match?(/[a-z0-9]/i))
              @temporary_buffer = "&" + match
              flush_code_points_consumed_as_character_reference
              @reconsume = false
              @state = @return_state
              return
            end
          end

          unless match.end_with?(";")
            parse_error("missing-semicolon-after-character-reference")
          end

          @temporary_buffer = ENTITIES["&#{match}"]["characters"].dup
          flush_code_points_consumed_as_character_reference
          @reconsume = false
          @state = @return_state
        else
          # No match: temporary buffer still holds "&". Flush and enter ambiguous ampersand.
          flush_code_points_consumed_as_character_reference
          reconsume(:ambiguous_ampersand)
        end
      end

      # §13.2.5.74 Ambiguous ampersand state
      def parse_ambiguous_ampersand_state
        case consume_next_input_character
        when /[a-z0-9]/i
          # If the character reference was consumed as part of an attribute, then append the current input character to the current attribute's value. Otherwise, emit the current input character as a character token.
          if consumed_as_part_of_an_attribute?
            append_to_current_attribute_value!(current_input_character)
          else
            emit(CharacterToken.new(current_input_character))
          end
        when ";"
          # This is an unknown-named-character-reference parse error. Reconsume in the return state.
          parse_error("unknown-named-character-reference")
          reconsume(@return_state)
        else
          # Reconsume in the return state.
          reconsume(@return_state)
        end
      end

      # §13.2.5.75 Numeric character reference state
      def parse_numeric_character_reference_state
        @character_reference_code = 0

        case consume_next_input_character
        when "x", "X"
          # Append the current input character to the temporary buffer. Switch to the hexadecimal character reference start state.
          @temporary_buffer << current_input_character
          switch_to(:hexadecimal_character_reference_start)
        else
          # Reconsume in the decimal character reference start state.
          reconsume(:decimal_character_reference_start)
        end
      end

      # §13.2.5.76 Hexadecimal character reference start state
      def parse_hexadecimal_character_reference_start_state
        case consume_next_input_character
        when /[0-9a-f]/i
          # Reconsume in the hexadecimal character reference state.
          reconsume(:hexadecimal_character_reference)
        else
          # This is an absence-of-digits-in-numeric-character-reference parse error. Flush code points consumed as a character reference. Reconsume in the return state.
          parse_error("absence-of-digits-in-numeric-character-reference")
          flush_code_points_consumed_as_character_reference
          reconsume(@return_state)
        end
      end

      # §13.2.5.77 Decimal character reference start state
      def parse_decimal_character_reference_start_state
        case consume_next_input_character
        when /[0-9]/
          # Reconsume in the decimal character reference state.
          reconsume(:decimal_character_reference)
        else
          # This is an absence-of-digits-in-numeric-character-reference parse error. Flush code points consumed as a character reference. Reconsume in the return state.
          parse_error("absence-of-digits-in-numeric-character-reference")
          flush_code_points_consumed_as_character_reference
          reconsume(@return_state)
        end
      end

      # §13.2.5.78 Hexadecimal character reference state
      def parse_hexadecimal_character_reference_state
        case consume_next_input_character
        when /[0-9]/
          # Multiply the character reference code by 16. Add a numeric version of the current input character (subtract 0x0030 from the character's code point) to the character reference code.
          @character_reference_code *= 16
          @character_reference_code += current_input_character.ord - 0x30
        when /[A-F]/
          # Multiply the character reference code by 16. Add a numeric version of the current input character as a hexadecimal digit (subtract 0x0037 from the character's code point) to the character reference code.
          @character_reference_code *= 16
          @character_reference_code += current_input_character.ord - 0x37
        when /[a-f]/
          # Multiply the character reference code by 16. Add a numeric version of the current input character as a hexadecimal digit (subtract 0x0057 from the character's code point) to the character reference code.
          @character_reference_code *= 16
          @character_reference_code += current_input_character.ord - 0x57
        when ";"
          # Switch to the numeric character reference end state.
          switch_to(:numeric_character_reference_end)
        else
          # This is a missing-semicolon-after-character-reference parse error. Reconsume in the numeric character reference end state.
          parse_error("missing-semicolon-after-character-reference")
          reconsume(:numeric_character_reference_end)
        end
      end

      # §13.2.5.79 Decimal character reference state
      def parse_decimal_character_reference_state
        case consume_next_input_character
        when /[0-9]/
          # Multiply the character reference code by 10. Add a numeric version of the current input character (subtract 0x0030 from the character's code point) to the character reference code.
          @character_reference_code *= 10
          @character_reference_code += current_input_character.ord - 0x30
        when ";"
          # Switch to the numeric character reference end state.
          switch_to(:numeric_character_reference_end)
        else
          # This is a missing-semicolon-after-character-reference parse error. Reconsume in the numeric character reference end state.
          parse_error("missing-semicolon-after-character-reference")
          reconsume(:numeric_character_reference_end)
        end
      end

      # §13.2.5.80 Numeric character reference end state
      def parse_numeric_character_reference_end_state
        code = @character_reference_code

        if code.zero?
          parse_error("null-character-reference")
          code = 0xFFFD
        elsif code > 0x10FFFF
          parse_error("character-reference-outside-unicode-range")
          code = 0xFFFD
        elsif code.between?(0xD800, 0xDFFF)
          parse_error("surrogate-character-reference")
          code = 0xFFFD
        end

        if noncharacter?(code)
          parse_error("noncharacter-character-reference")
        end

        if code == 0x0D || (control_character?(code) && !ascii_whitespace_code?(code))
          parse_error("control-character-reference")
          code = CHARACTER_REFERENCE_CODE_OVERRIDES.fetch(code, code)
        end

        @temporary_buffer = +""
        @temporary_buffer << code
        flush_code_points_consumed_as_character_reference
        @state = @return_state
      end

      private

      def noncharacter?(code)
        code.between?(0xFDD0, 0xFDEF) ||
          (code & 0xFFFE) == 0xFFFE && code <= 0x10FFFF
      end

      def control_character?(code)
        code.between?(0x01, 0x08) ||
          code == 0x0B ||
          code.between?(0x0E, 0x1F) ||
          code.between?(0x7F, 0x9F)
      end

      def ascii_whitespace_code?(code)
        [0x09, 0x0A, 0x0C, 0x0D, 0x20].include?(code)
      end
    end
  end
end
