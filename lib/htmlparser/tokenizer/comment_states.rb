# frozen_string_literal: true

module HTMLParser
  class Tokenizer
    # Tokenizer states for WHATWG HTML §13.2.5 (see method comments).
    module CommentStates
      # §13.2.5.41 Bogus comment state
      def parse_bogus_comment_state
        case consume_next_input_character
        when ">"
          # Switch to the data state. Emit the current comment token.
          switch_to_and_emit(:data, @comment_token)
        when EOF
          # Emit the comment. Emit an end-of-file token.
          emit(@comment_token)
          emit_eof!
        when "\u0000"
          # This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the comment token's data.
          parse_error("unexpected-null-character")
          @comment_token.data << "\ufffd"
        else
          # Append the current input character to the comment token's data.
          @comment_token.data << current_input_character
        end
      end

      # §13.2.5.42 Markup declaration open state
      def parse_markup_declaration_open_state
        if next_characters_are?("--")
          # Consume those two characters, create a comment token whose data is the empty string, and switch to the comment start state.
          consume_characters(2)
          @comment_token = new_comment_token
          switch_to(:comment_start)
        elsif next_characters_are?("DOCTYPE", case_insensitive: true)
          # Consume those characters and switch to the DOCTYPE state.
          consume_characters(7)
          switch_to(:doctype)
        elsif next_characters_are?("[CDATA[")
          # Consume those characters. If there is an adjusted current node and it is not an element in the HTML namespace, then switch to the CDATA section state. Otherwise, this is a cdata-in-html-content parse error. Create a comment token whose data is the "[CDATA[" string. Switch to the bogus comment state.
          consume_characters(7)
          node = @adjusted_current_node_provider&.call
          if node && !node.html?
            switch_to(:cdata_section)
          else
            parse_error("cdata-in-html-content")
            @comment_token = new_comment_token(+"[CDATA[")
            switch_to(:bogus_comment)
          end
        else
          # This is an incorrectly-opened-comment parse error. Create a comment token whose data is the empty string. Switch to the bogus comment state (don't consume anything in the current state).
          # Peeked next character may need an input-stream error before this tokenizer error
          # (html5lib order for e.g. <!\u000B).
          if report_input_stream_character_errors(next_input_character)
            @skip_next_input_stream_error_report = true
          end
          parse_error("incorrectly-opened-comment")
          @comment_token = new_comment_token
          switch_to(:bogus_comment)
        end
      end

      # §13.2.5.43 Comment start state
      def parse_comment_start_state
        case consume_next_input_character
        when "-"
          # Switch to the comment start dash state.
          switch_to(:comment_start_dash)
        when ">"
          # This is an abrupt-closing-of-empty-comment parse error. Switch to the data state. Emit the current comment token.
          parse_error("abrupt-closing-of-empty-comment")
          switch_to_and_emit(:data, @comment_token)
        else
          # Reconsume in the comment state.
          reconsume(:comment)
        end
      end

      # §13.2.5.44 Comment start dash state
      def parse_comment_start_dash_state
        case consume_next_input_character
        when "-"
          # Switch to the comment end state.
          switch_to(:comment_end)
        when ">"
          # This is an abrupt-closing-of-empty-comment parse error. Switch to the data state. Emit the current comment token.
          parse_error("abrupt-closing-of-empty-comment")
          switch_to_and_emit(:data, @comment_token)
        when EOF
          # This is an eof-in-comment parse error. Emit the current comment token. Emit an end-of-file token.
          emit_eof_in_comment!
        else
          # Append a U+002D HYPHEN-MINUS character (-) to the comment token's data. Reconsume in the comment state.
          @comment_token.data << "-"
          reconsume(:comment)
        end
      end

      # §13.2.5.45 Comment state
      def parse_comment_state
        case consume_next_input_character
        when "<"
          # Append the current input character to the comment token's data. Switch to the comment less-than sign state.
          @comment_token.data << current_input_character
          switch_to(:comment_less_than_sign)
        when "-"
          # Switch to the comment end dash state.
          switch_to(:comment_end_dash)
        when "\u0000"
          # This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the comment token's data.
          parse_error("unexpected-null-character")
          @comment_token.data << "\ufffd"
        when EOF
          # This is an eof-in-comment parse error. Emit the current comment token. Emit an end-of-file token.
          emit_eof_in_comment!
        else
          # Append the current input character to the comment token's data.
          @comment_token.data << current_input_character
        end
      end

      # §13.2.5.46 Comment less-than sign state
      def parse_comment_less_than_sign_state
        case consume_next_input_character
        when "!"
          # Append the current input character to the comment token's data. Switch to the comment less-than sign bang state.
          @comment_token.data << current_input_character
          switch_to(:comment_less_than_sign_bang)
        when "<"
          # Append the current input character to the comment token's data.
          @comment_token.data << current_input_character
        else
          # Reconsume in the comment state.
          reconsume(:comment)
        end
      end

      # §13.2.5.47 Comment less-than sign bang state
      def parse_comment_less_than_sign_bang_state
        case consume_next_input_character
        when "-"
          # Switch to the comment less-than sign bang dash state.
          switch_to(:comment_less_than_sign_bang_dash)
        else
          # Reconsume in the comment state.
          reconsume(:comment)
        end
      end

      # §13.2.5.48 Comment less-than sign bang dash state
      def parse_comment_less_than_sign_bang_dash_state
        case consume_next_input_character
        when "-"
          # Switch to the comment less-than sign bang dash dash state.
          switch_to(:comment_less_than_sign_bang_dash_dash)
        else
          # Reconsume in the comment end dash state.
          reconsume(:comment_end_dash)
        end
      end

      # §13.2.5.49 Comment less-than sign bang dash dash state
      def parse_comment_less_than_sign_bang_dash_dash_state
        case consume_next_input_character
        when ">", EOF
          # Reconsume in the comment end state.
        else
          # This is a nested-comment parse error. Reconsume in the comment end state.
          parse_error("nested-comment")
        end
        reconsume(:comment_end)
      end

      # §13.2.5.50 Comment end dash state
      def parse_comment_end_dash_state
        case consume_next_input_character
        when "-"
          # Switch to the comment end state.
          switch_to(:comment_end)
        when EOF
          # This is an eof-in-comment parse error. Emit the current comment token. Emit an end-of-file token.
          emit_eof_in_comment!
        else
          # Append a U+002D HYPHEN-MINUS character (-) to the comment token's data. Reconsume in the comment state.
          @comment_token.data << "-"
          reconsume(:comment)
        end
      end

      # §13.2.5.51 Comment end state
      def parse_comment_end_state
        case consume_next_input_character
        when ">"
          # Switch to the data state. Emit the current comment token.
          switch_to(:data)
          emit(@comment_token)
        when "!"
          # Switch to the comment end bang state.
          switch_to(:comment_end_bang)
        when "-"
          # Append a U+002D HYPHEN-MINUS character (-) to the comment token's data.
          @comment_token.data << "-"
        when EOF
          # This is an eof-in-comment parse error. Emit the current comment token. Emit an end-of-file token.
          emit_eof_in_comment!
        else
          # Append two U+002D HYPHEN-MINUS characters (-) to the comment token's data. Reconsume in the comment state.
          @comment_token.data << "--"
          reconsume(:comment)
        end
      end

      # §13.2.5.52 Comment end bang state
      def parse_comment_end_bang_state
        case consume_next_input_character
        when "-"
          # Append two U+002D HYPHEN-MINUS characters (-) and a U+0021 EXCLAMATION MARK character (!) to the comment token's data. Switch to the comment end dash state.
          @comment_token.data << "--!"
          switch_to(:comment_end_dash)
        when ">"
          # This is an incorrectly-closed-comment parse error. Switch to the data state. Emit the current comment token.
          parse_error("incorrectly-closed-comment")
          switch_to_and_emit(:data, @comment_token)
        when EOF
          # This is an eof-in-comment parse error. Emit the current comment token. Emit an end-of-file token.
          emit_eof_in_comment!
        else
          # Append two U+002D HYPHEN-MINUS characters (-) and a U+0021 EXCLAMATION MARK character (!) to the comment token's data. Reconsume in the comment state.
          @comment_token.data << "--!"
          reconsume(:comment)
        end
      end
    end
  end
end
