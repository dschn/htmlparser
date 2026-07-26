# frozen_string_literal: true

module HTMLParser
  class Tokenizer
    # Tokenizer states for WHATWG HTML §13.2.5 CDATA section.
    module CdataStates
      # §13.2.5.69 CDATA section state
      def parse_cdata_section_state
        case consume_next_input_character
        when "]"
          # Switch to the CDATA section bracket state.
          switch_to(:cdata_section_bracket)
        when EOF
          # This is an eof-in-cdata parse error. Emit an end-of-file token.
          parse_error("eof-in-cdata")
          emit_eof!
        else
          # Emit the current input character as a character token.
          # U+0000 NULL characters are handled in the tree construction stage…
          emit(CharacterToken.new(current_input_character))
        end
      end

      # §13.2.5.70 CDATA section bracket state
      def parse_cdata_section_bracket_state
        case consume_next_input_character
        when "]"
          # Switch to the CDATA section end state.
          switch_to(:cdata_section_end)
        else
          # Emit a U+005D RIGHT SQUARE BRACKET character token. Reconsume in the CDATA section state.
          emit(CharacterToken.new("]"))
          reconsume(:cdata_section)
        end
      end

      # §13.2.5.71 CDATA section end state
      def parse_cdata_section_end_state
        case consume_next_input_character
        when "]"
          # Emit a U+005D RIGHT SQUARE BRACKET character token.
          emit(CharacterToken.new("]"))
        when ">"
          # Switch to the data state.
          switch_to(:data)
        else
          # Emit two U+005D RIGHT SQUARE BRACKET character tokens. Reconsume in the CDATA section state.
          emit(CharacterToken.new("]"))
          emit(CharacterToken.new("]"))
          reconsume(:cdata_section)
        end
      end
    end
  end
end
