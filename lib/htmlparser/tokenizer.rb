# frozen_string_literal: true

# TODO: log parse errors
# TODO: @state = @return_state switch_to(), see if @reconsume reset still needed

require 'strscan'
require 'json'

module HTMLParser
  class StartTagToken
    attr_accessor :name, :attributes, :self_closing

    def initialize(name)
      @name = name
      @attributes = []
      @self_closing = false
    end
  end

  class EndTagToken
    attr_accessor :name

    def initialize(name)
      @name = name
    end
  end

  class CharacterToken
    attr_accessor :value

    def initialize(value)
      @value = value
    end
  end

  class DocTypeToken
    attr_accessor :name

    def initialize(name)
      @name = name
    end
  end

  class CommentToken
    attr_accessor :data

    def initialize(data)
      @data = data
    end
  end

  class Tokenizer
    EOF = nil # assuming nil is EOF for stringscanner, @input_stream.eos? probably better
    ENTITIES = JSON.parse(File.read('entities.json'))
    ENTITIES_KEYS = ENTITIES.keys.map { |x| x.delete_prefix('&') }
    WHITESPACE = ["\u0009", "\u000a", "\u000c", "\u0020"].freeze
    PART_OF_AN_ATTRIBUTE = %i[
      attribute_value_double_quoted
      attribute_value_single_quoted
      attribute_value_unquoted
    ].freeze

    def initialize(input_stream)
      @input_stream = input_stream
      @return_state = nil
      @state = :data
      @current_tag_token = nil
      @comment_token = nil
      @temporary_buffer = nil
      @reconsume = false
      @tokens = Queue.new
    end

    def parse
      until @input_stream.eos?
        parse_state_method = "parse_#{@state}_state"

        if respond_to?(parse_state_method, true)
          send(parse_state_method)

          yield @tokens.pop until @tokens.empty?
        else
          raise "unimp #{@state}"
        end
      end
    end

    private

    attr_reader :current_input_character

    def consume_next_input_character
      @current_input_character = @input_stream.getch unless @reconsume

      @reconsume = false
      @current_input_character
    end

    def reconsume(state)
      @reconsume = true
      switch_to(state)
    end

    def return_to_and_switch_to(return_state, state)
      @return_state = return_state
      switch_to(state)
    end

    def switch_to(state)
      @state = state
    end

    def switch_to_and_emit(state, token)
      switch_to(state)
      emit(token)
    end

    def emit(token)
      @tokens << token
    end

    def consumed_as_part_of_an_attribute?
      PART_OF_AN_ATTRIBUTE.include?(@return_to)
    end

    def flush_code_points_consumed_as_character_reference
      # When a state says to flush code points consumed as a character
      # reference, it means that for each code point in the temporary
      # buffer (in the order they were added to the buffer) user agent
      # must append the code point from the buffer to the current
      # attribute's value if the character reference was consumed as
      # part of an attribute, or emit the code point as a character
      # token otherwise.

      # TODO: consolidate as flush code points consumed as character reference
      if consumed_as_part_of_an_attribute?
        # FIXME: is this supposed to be nil sometimes?
        @current_tag_token.attributes.last[:value] << @temporary_buffer.to_s
      else
        emit(CharacterToken.new(@temporary_buffer))
      end
    end

    # 13.2.5.1 Data state
    def parse_data_state
      case consume_next_input_character
      when '&'
        # Set the return state to the data state. Switch to the character reference state.
        return_to_and_switch_to(:data, :character_reference)
      when '<'
        # Switch to the tag open state.
        switch_to(:tag_open)
      when "\u0000"
        # This is an unexpected-null-character parse error. Emit the current input character as a character token.
        not_implemented('unexpected-null-character')
      when EOF
        # Emit an end-of-file token.
        not_implemented('EOF')
      else
        # Emit the current input character as a character token.
        emit(CharacterToken.new(current_input_character))
      end
    end

    # 13.2.5.6 Tag open state
    def parse_tag_open_state
      case consume_next_input_character
      when '!'
        # Switch to the markup declaration open state.
        switch_to(:markup_declaration_open)
      when '/'
        # Switch to the end tag open state.
        switch_to(:end_tag_open)
      when /[a-z]/i # ASCII alpha
        # Create a new start tag token, set its tag name to the empty string. Reconsume in the tag name state.
        @current_tag_token = StartTagToken.new(String.new)
        reconsume(:tag_name)
      when '?'
        # This is an unexpected-question-mark-instead-of-tag-name parse error. Create a comment token whose data is the empty string. Reconsume in the bogus comment state.
        not_implemented
      when EOF
        # This is an eof-before-tag-name parse error. Emit a U+003C LESS-THAN SIGN character token and an end-of-file token.
        not_implemented('EOF')
      else
        # This is an invalid-first-character-of-tag-name parse error. Emit a U+003C LESS-THAN SIGN character token. Reconsume in the data state.
        emit(CharacterToken.new("\u003c"))
        reconsume(:data)
      end
    end

    # 13.2.5.7 End tag open state
    def parse_end_tag_open_state
      case consume_next_input_character
      when /[a-z]/i
        # Create a new end tag token, set its tag name to the empty string. Reconsume in the tag name state.
        @current_tag_token = EndTagToken.new(String.new)
        reconsume(:tag_name)
      when '>'
        # This is a missing-end-tag-name parse error. Switch to the data state.
        switch_to(:data)
      when EOF
        # This is an eof-before-tag-name parse error. Emit a U+003C LESS-THAN SIGN character token, a U+002F SOLIDUS character token and an end-of-file token.
        not_implemented('EOF')
      else
        # This is an invalid-first-character-of-tag-name parse error. Create a comment token whose data is the empty string. Reconsume in the bogus comment state.
        not_implemented('else')
      end
    end

    # 13.2.5.8 Tag name state
    def parse_tag_name_state
      case consume_next_input_character
      when *WHITESPACE
        # Switch to the before attribute name state.
        switch_to(:before_attribute_name)
      when '/'
        # Switch to the self-closing start tag state.
        switch_to(:self_closing_start_tag)
      when '>'
        # Switch to the data state. Emit the current tag token.
        switch_to(:data)
        emit(@current_tag_token)
      when /[A-Z]/
        # Append the lowercase version of the current input character (add 0x0020 to the character's code point) to the current tag token's tag name.
        @current_tag_token.name << current_input_character.downcase
      when "\u0000" # U+0000 NULL
        # This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current tag token's tag name.
        not_implemented('null')
      when EOF
        # This is an eof-in-tag parse error. Emit an end-of-file token.
        not_implemented('EOF')
      else
        # Append the current input character to the current tag token's tag name.
        @current_tag_token.name << current_input_character
      end
    end

    # 13.2.5.32 Before attribute name state
    def parse_before_attribute_name_state
      case consume_next_input_character
      when *WHITESPACE
        # Ignore the character.
      when '/', '>', EOF
        # Reconsume in the after attribute name state.
        # not_implemented("reconsume in after attribute name state")
        reconsume(:after_attribute_name)
      when '='
        # This is an unexpected-equals-sign-before-attribute-name parse error. Start a new attribute in the current tag token. Set that attribute's name to the current input character, and its value to the empty string. Switch to the attribute name state.
        not_implemented
      else
        # Start a new attribute in the current tag token. Set that attribute name and value to the empty string. Reconsume in the attribute name state.
        @current_tag_token.attributes << { name: String.new, value: String.new } # TODO: track index
        reconsume(:attribute_name)
      end
    end

    # 13.2.5.33 Attribute name state
    def parse_attribute_name_state
      case consume_next_input_character
      when *WHITESPACE
      when "\u002f", "\u003e", EOF
        # Reconsume in the after attribute name state.
        reconsume(:after_attribute_name)
      when '='
        # Switch to the before attribute value state.
        switch_to(:before_attribute_value)
      when /[A-Z]/
        # Append the lowercase version of the current input character (add 0x0020 to the character's code point) to the current attribute's name.
        @current_tag_token.attributes.last[:name] << current_input_character.downcase
      when "\u0000"
        # This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current attribute's name.
        not_implemented('null')
      # U+0022 QUOTATION MARK (")
      # U+0027 APOSTROPHE (')
      # U+003C LESS-THAN SIGN (<)
      when "\u0022", "\u0027", "\u003c"
        # This is an unexpected-character-in-attribute-name parse error. Treat it as per the "anything else" entry below.
        @current_tag_token.attributes.last[:name] << current_input_character
      else
        # Append the current input character to the current attribute's name.
        @current_tag_token.attributes.last[:name] << current_input_character
      end
    end

    # 13.2.5.34 After attribute name state
    def parse_after_attribute_name_state
      case consume_next_input_character
      when *WHITESPACE
        # Ignore the character.
      when '/'
        # Switch to the self-closing start tag state.
        switch_to(:self_closing_start_tag)
      when '='
        # Switch to the before attribute value state.
        switch_to(:before_attribute_value)
      when '>'
        # Switch to the data state. Emit the current tag token.
        switch_to_and_emit(:data, @current_tag_token)
      when EOF
        # This is an eof-in-tag parse error. Emit an end-of-file token.
        not_implemented('EOF')
      else
        # Start a new attribute in the current tag token. Set that attribute name and value to the empty string. Reconsume in the attribute name state.
        @current_tag_token.attributes << { name: String.new, value: String.new }
        reconsume(:attribute_name)
      end
    end

    # 13.2.5.35 Before attribute value state
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
      when '>'
        # This is a missing-attribute-value parse error. Switch to the data state. Emit the current tag token.
        switch_to(:data)
        emit(@current_tag_token)
      else
        # Reconsume in the attribute value (unquoted) state.
        reconsume(:attribute_value_unquoted)
      end
    end

    # 13.2.5.36 Attribute value (double-quoted) state
    def parse_attribute_value_double_quoted_state
      case consume_next_input_character
      when '"'
        # Switch to the after attribute value (quoted) state.
        switch_to(:after_attribute_value_quoted)
      when '&'
        # Set the return state to the attribute value (double-quoted) state. Switch to the character reference state.
        return_to_and_switch_to(:attribute_value_double_quoted, :character_reference)
      when "\u0000"
        # This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current attribute's value.
        not_implemented('null')
      when EOF
        # This is an eof-in-tag parse error. Emit an end-of-file token.
        not_implemented('EOF')
      else
        # Append the current input character to the current attribute's value.
        @current_tag_token.attributes.last[:value] << current_input_character
      end
    end

    # 13.2.5.37 Attribute value (single-quoted) state
    def parse_attribute_value_single_quoted_state
      case consume_next_input_character
      when "'"
        # Switch to the after attribute value (quoted) state.
        switch_to(:after_attribute_value_quoted)
      when '&'
        # Set the return state to the attribute value (single-quoted) state. Switch to the character reference state.
        return_to_and_switch_to(:attribute_value_single_quoted, :character_reference)
      when "\u0000"
        # This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current attribute's value.
        not_implemented('null')
      when EOF
        # This is an eof-in-tag parse error. Emit an end-of-file token.
        not_implemented('EOF')
      else
        # Append the current input character to the current attribute's value.
        @current_tag_token.attributes.last[:value] << current_input_character
      end
    end

    # 13.2.5.38 Attribute value (unquoted) state
    def parse_attribute_value_unquoted_state
      case consume_next_input_character
      when *WHITESPACE
        # Switch to the before attribute name state.
        switch_to(:before_attribute_name)
      when '&'
        # Set the return state to the attribute value (unquoted) state. Switch to the character reference state.
        return_to_and_switch_to(:attribute_value_unquoted, :character_reference)
      when '>'
        # Switch to the data state. Emit the current tag token.
        switch_to_and_emit(:data, @current_tag_token)
      when "\u0000"
        # This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current attribute's value.
        not_implemented('??')
      when '"', "'", '<', '=', '`'
        # This is an unexpected-character-in-unquoted-attribute-value parse error. Treat it as per the "anything else" entry below.
        @current_tag_token.attributes.last[:value] << current_input_character
      when EOF
        # This is an eof-in-tag parse error. Emit an end-of-file token.
        not_implemented('EOF')
      else
        # Append the current input character to the current attribute's value.
        @current_tag_token.attributes.last[:value] << current_input_character
      end
    end

    # 13.2.5.39 After attribute value (quoted) state
    def parse_after_attribute_value_quoted_state
      case consume_next_input_character
      when *WHITESPACE
        # Switch to the before attribute name state.
        switch_to(:before_attribute_name)
      when '/'
        # Switch to the self-closing start tag state.
        switch_to(:self_closing_start_tag)
      when '>'
        # Switch to the data state. Emit the current tag token.
        switch_to_and_emit(:data, @current_tag_token)
      when EOF
        # This is an eof-in-tag parse error. Emit an end-of-file token.
        not_implemented('EOF')
      else
        # This is a missing-whitespace-between-attributes parse error. Reconsume in the before attribute name state.
        reconsume(:before_attribute_name)
      end
    end

    # 13.2.5.40 Self-closing start tag state
    def parse_self_closing_start_tag_state
      case consume_next_input_character
      when '>'
        # Set the self-closing flag of the current tag token. Switch to the data state. Emit the current tag token.
        @current_tag_token.self_closing = true
        switch_to_and_emit(:data, @current_tag_token)
      when EOF
        # This is an eof-in-tag parse error. Emit an end-of-file token.
        not_implemented('EOF')
      else
        # This is an unexpected-solidus-in-tag parse error. Reconsume in the before attribute name state.
        reconsume(:before_attribute_name)
      end
    end

    # 13.2.5.42 Markup declaration open state
    def parse_markup_declaration_open_state
      # FIXME: Skip keeps looking when spec says "next N characters"
      if @input_stream.skip('--')
        # Consume those two characters, create a comment token whose data is the empty string, and switch to the comment start state.
        @comment_token = CommentToken.new(String.new)
        switch_to(:comment_start)
      # FIXME: Skip keeps looking when spec says "next N characters"
      elsif @input_stream.skip(/doctype/i)
        # Consume those characters and switch to the DOCTYPE state.
        switch_to(:doctype)
      elsif next_input_character == '[' && @input_stream.skip('CDATA[')
        # Consume those characters. If there is an adjusted current node and it is not an element in the HTML namespace, then switch to the CDATA section state. Otherwise, this is a cdata-in-html-content parse error. Create a comment token whose data is the "[CDATA[" string. Switch to the bogus comment state.
        not_implemented('CDATA :(')
      else
        # This is an incorrectly-opened-comment parse error. Create a comment token whose data is the empty string. Switch to the bogus comment state (don't consume anything in the current state).
        not_implemented('else')
      end
    end

    # 13.2.5.43 Comment start state
    def parse_comment_start_state
      case consume_next_input_character
      when '-'
        # Switch to the comment start dash state.
        switch_to(:comment_start_dash)
      when '>'
        # This is an abrupt-closing-of-empty-comment parse error. Switch to the data state. Emit the current comment token.
        switch_to_and_emit(:data, @comment_token)
      else
        # Reconsume in the comment state.
        reconsume(:comment)
      end
    end

    # 13.2.5.44 Comment start dash state
    def parse_comment_start_dash_state
      case consume_next_input_character
      when '-'
        # Switch to the comment end state.
        switch_to(:comment_end)
      when '>'
        # This is an abrupt-closing-of-empty-comment parse error. Switch to the data state. Emit the current comment token.
        switch_to_and_emit(:data, @comment_token)
      when EOF
        # This is an eof-in-comment parse error. Emit the current comment token. Emit an end-of-file token.
        not_implemented('EOF')
      else
        # Append a U+002D HYPHEN-MINUS character (-) to the comment token's data. Reconsume in the comment state.
        @comment_token.data << '-'
        reconsume(:comment)
      end
    end

    # 13.2.5.45 Comment state
    def parse_comment_state
      case consume_next_input_character
      when '<'
        # Append the current input character to the comment token's data. Switch to the comment less-than sign state.
        @comment_token.data << current_input_character
        switch_to(:comment_less_than_sign)
      when '-'
        # Switch to the comment end dash state.
        switch_to(:comment_end_dash)
      when "\u0000"
        # This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the comment token's data.
        @comment_token.data << "\ufffd"
      when EOF
        # This is an eof-in-comment parse error. Emit the current comment token. Emit an end-of-file token.
        not_implemented('EOF')
      else
        # Append the current input character to the comment token's data.
        @comment_token.data << current_input_character
      end
    end

    # 13.2.5.46 Comment less-than sign state
    def parse_comment_less_than_sign_state
      case consume_next_input_character
      when '!'
        # Append the current input character to the comment token's data. Switch to the comment less-than sign bang state.
        @comment_token.data << current_input_character
        switch_to(:comment_less_than_sign_bang)
      when '<'
        # Append the current input character to the comment token's data.
        @comment_token.data << current_input_character
      else
        # Reconsume in the comment state.
        reconsume(:comment)
      end
    end

    # 13.2.5.47 Comment less-than sign bang state
    def parse_comment_less_than_sign_bang_state
      case consume_next_input_character
      when '!'
        # Switch to the comment less-than sign bang dash state.
        switch_to(:comment_less_than_sign_bang_dash)
      else
        # Reconsume in the comment state.
        reconsume(:comment)
      end
    end

    # 13.2.5.50 Comment end dash state
    def parse_comment_end_dash_state
      case consume_next_input_character
      when '-'
        # Switch to the comment end state.
        switch_to(:comment_end)
      when EOF
        # This is an eof-in-comment parse error. Emit the current comment token. Emit an end-of-file token.
        not_implemented('EOF')
      else
        # Append a U+002D HYPHEN-MINUS character (-) to the comment token's data. Reconsume in the comment state.
        @comment_token.data << '-'
        reconsume(:comment)
      end
    end

    # 13.2.5.51 Comment end state
    def parse_comment_end_state
      case consume_next_input_character
      when '>'
        # Switch to the data state. Emit the current comment token.
        switch_to(:data)
        emit(@comment_token)
      when '!'
        # Switch to the comment end bang state.
        switch_to(:comment_end_bang)
      when '-'
        # Append a U+002D HYPHEN-MINUS character (-) to the comment token's data.
        @comment_token.data << '-'
      when EOF
        # This is an eof-in-comment parse error. Emit the current comment token. Emit an end-of-file token.
        not_implemented('EOF')
      else
        # Append two U+002D HYPHEN-MINUS characters (-) to the comment token's data. Reconsume in the comment state.
        @comment_token.data << '-'
        reconsume(:comment)
      end
    end

    # 13.2.5.53 DOCTYPE state
    def parse_doctype_state
      case consume_next_input_character
      when *WHITESPACE
        # Switch to the before DOCTYPE name state.
        switch_to(:before_doctype_name)
      when '>'
        # Reconsume in the before DOCTYPE name state.
        not_implemented
      when EOF
        # This is an eof-in-doctype parse error. Create a new DOCTYPE token. Set its force-quirks flag to on. Emit the current token. Emit an end-of-file token.
        not_implemented('EOF')
      else
        # This is a missing-whitespace-before-doctype-name parse error. Reconsume in the before DOCTYPE name state.
        not_implemented('else')
      end
    end

    # 13.2.5.54 Before DOCTYPE name state
    def parse_before_doctype_name_state
      case consume_next_input_character
      when *WHITESPACE
        # Ignore the character
      when /[A-Z]/
        # Create a new DOCTYPE token. Set the token's name to the lowercase version of the current input character (add 0x0020 to the character's code point). Switch to the DOCTYPE name state.
        not_implemented('a-z')
      when "\u0000"
        # This is an unexpected-null-character parse error. Create a new DOCTYPE token. Set the token's name to a U+FFFD REPLACEMENT CHARACTER character. Switch to the DOCTYPE name state.
        not_implemented('null')
      when '>'
        # This is a missing-doctype-name parse error. Create a new DOCTYPE token. Set its force-quirks flag to on. Switch to the data state. Emit the current token.
        not_implemented('>')
      when EOF
        # This is an eof-in-doctype parse error. Create a new DOCTYPE token. Set its force-quirks flag to on. Emit the current token. Emit an end-of-file token.
        not_implemented('EOF')
      else
        # Create a new DOCTYPE token. Set the token's name to the current input character. Switch to the DOCTYPE name state.
        @current_tag_token = DocTypeToken.new(current_input_character)
        switch_to(:doctype_name)
      end
    end

    # 13.2.5.55 DOCTYPE name state
    def parse_doctype_name_state
      case consume_next_input_character
      when *WHITESPACE
        # Switch to the after DOCTYPE name state.
        switch_to(:after_doctype_name)
      when '>'
        # Switch to the data state. Emit the current DOCTYPE token.
        switch_to_and_emit(:data, @current_tag_token)
      when /[A-Z]/
        # Append the lowercase version of the current input character (add 0x0020 to the character's code point) to the current DOCTYPE token's name.
        not_implemented('A-Z')
      when "\u0000"
        # This is an unexpected-null-character parse error. Append a U+FFFD REPLACEMENT CHARACTER character to the current DOCTYPE token's name.
        not_implemented('null')
      when EOF
        # This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
        not_implemented('EOF')
      else
        @current_tag_token.name << current_input_character
      end
    end

    # 13.2.5.56 After DOCTYPE name state
    def parse_after_doctype_name_state
      case consume_next_input_character
      when *WHITESPACE
        # Ignore the character.
      when '>'
        # Switch to the data state. Emit the current DOCTYPE token.
        emit(@current_tag_token)
      when EOF
        # This is an eof-in-doctype parse error. Set the current DOCTYPE token's force-quirks flag to on. Emit the current DOCTYPE token. Emit an end-of-file token.
        not_implemented('EOF')
      else
        # If the six characters starting from the current input character are an ASCII case-insensitive match for the word "PUBLIC", then consume those characters and switch to the after DOCTYPE public keyword state.
        # Otherwise, if the six characters starting from the current input character are an ASCII case-insensitive match for the word "SYSTEM", then consume those characters and switch to the after DOCTYPE system keyword state.
        # Otherwise, this is an invalid-character-sequence-after-doctype-name parse error. Set the current DOCTYPE token's force-quirks flag to on. Reconsume in the bogus DOCTYPE state.
        not_implemented('else')
      end
    end

    # 13.2.5.72 Character reference state
    def parse_character_reference_state
      # Set the temporary buffer to the empty string. Append a U+0026 AMPERSAND (&) character to the temporary buffer. Consume the next input character:
      @temporary_buffer = String.new

      case consume_next_input_character
      when /[a-z0-9]/i
        # Reconsume in the named character reference state.
        reconsume(:named_character_reference)
      when '#'
        # Append the current input character to the temporary buffer. Switch to the numeric character reference state.
        @temporary_buffer << current_input_character
        switch_to(:numeric_character_reference)
      else
        # Flush code points consumed as a character reference. Reconsume in the return state.
        flush_code_points_consumed_as_character_reference
        reconsume(@return_state)
      end
    end

    # 13.2.5.73 Named character reference state
    def parse_named_character_reference_state
      substring = @input_stream.string[@input_stream.charpos - 1..-1][0..100]
      match = nil

      ENTITIES_KEYS.each do |entity_name|
        match = entity_name if substring.start_with?(entity_name)
      end

      if match
        @input_stream.pos += (match.size - 1)
        @temporary_buffer << ENTITIES["&#{match}"]['characters']

        # FIXME: untested, chaos here
        if consumed_as_part_of_an_attribute? && !match.end_with?(';')
          next_character = @input_stream.peek(1)
          if next_character && (next_character == '=' || next_character =~ /a-z0-9/i)
            flush_code_points_consumed_as_character_reference
            @reconsume = false
            @state = @return_state
            return
          end
        end

        not_implemented('missing-semicolon-after-character-reference') unless match.end_with?(';')

        @temporary_buffer = ENTITIES["&#{match}"]['characters']
        flush_code_points_consumed_as_character_reference
        @reconsume = false
        @state = @return_state
        nil
      else
        # FIXME: this doesn't seem right but works - other parsers seem to be confused here too
        flush_code_points_consumed_as_character_reference
        reconsume(:ambiguous_ampersand)
      end
    end

    # 13.2.5.74 Ambiguous ampersand state
    def parse_ambiguous_ampersand_state
      case consume_next_input_character
      when /a-z0-9/i
        # If the character reference was consumed as part of an attribute, then append the current input character to the current attribute's value. Otherwise, emit the current input character as a character token.
        if consumed_as_part_of_an_attribute?
          @current_tag_token.attributes.last[:value] << current_input_character
        else
          emit(CharacterToken.new(current_input_character))
        end
      when ';'
        # This is an unknown-named-character-reference parse error. Reconsume in the return state.
        not_implemented('unknown-named-character-reference')
      else
        # Reconsume in the return state.
        reconsume(@return_state)
      end
    end

    # 13.2.5.75 Numeric character reference state
    def parse_numeric_character_reference_state
      @character_reference_code = 0

      case consume_next_input_character
      when 'x', 'X'
        # Append the current input character to the temporary buffer. Switch to the hexadecimal character reference start state.
        @temporary_buffer << current_input_character
        switch_to(:hexadecimal_character_reference_start)
      else
        # Reconsume in the decimal character reference start state.
        reconsume(:decimal_character_reference_start)
      end
    end

    # 13.2.5.76 Hexadecimal character reference start state
    def parse_hexadecimal_character_reference_start_state
      case consume_next_input_character
      # ASCII hex digit
      when /[a-f]/i
        # Reconsume in the hexadecimal character reference state.
        reconsume(:hexadecimal_character_reference)
      else
        # This is an absence-of-digits-in-numeric-character-reference parse error. Flush code points consumed as a character reference. Reconsume in the return state.
        flush_code_points_consumed_as_character_reference
        reconsume(@return_state)
      end
    end

    # 13.2.5.77 Decimal character reference start state
    def parse_decimal_character_reference_start_state
      case consume_next_input_character
      when /[0-9]/
        # Reconsume in the decimal character reference state.
        reconsume(:decimal_character_reference)
      else
        # This is an absence-of-digits-in-numeric-character-reference parse error. Flush code points consumed as a character reference. Reconsume in the return state.
        flush_code_points_consumed_as_character_reference
        reconsume(@return_state)
      end
    end

    # 13.2.5.78 Hexadecimal character reference state
    def parse_hexadecimal_character_reference_state
      # Consume the next input character:
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
      when ';'
        # Switch to the numeric character reference end state.
        switch_to(:numeric_character_reference_end)
      else
        # This is a missing-semicolon-after-character-reference parse error. Reconsume in the numeric character reference end state.
        # log_parse_error()
        reconsume(:numeric_character_reference_end)
      end
    end

    # 13.2.5.79 Decimal character reference state
    def parse_decimal_character_reference_state
      case consume_next_input_character
      when /[0-9]/
        # Multiply the character reference code by 10. Add a numeric version of the current input character (subtract 0x0030 from the character's code point) to the character reference code.
        @character_reference_code *= 10
        @character_reference_code += current_input_character.ord - 0x30
      when ';'
        # Switch to the numeric character reference end state.
        switch_to(:numeric_character_reference_end)
      else
        # This is a missing-semicolon-after-character-reference parse error. Reconsume in the numeric character reference end state.
        # log_parse_error
        reconsume(:character_reference_end)
      end
    end

    # 13.2.5.80 Numeric character reference end state
    def parse_numeric_character_reference_end_state
      @character_reference_code = 0xFFFD if @character_reference_code.zero?

      @character_reference_code = 0xFFFD if @character_reference_code > 0x10ffff

      @character_reference_code = 0xFFFD if @character_reference_code.between?(0xD800, 0xDFFF)

      # If the number is a noncharacter, then this is a noncharacter-character-reference parse error.
      # If the number is 0x0D, or a control that's not ASCII whitespace, then this is a control-character-reference parse error. If the number is one of the numbers in the first column of the following table, then find the row with that number in the first column, and set the character reference code to the number in the second column of that row.

      @temporary_buffer = String.new
      @temporary_buffer << @character_reference_code
      flush_code_points_consumed_as_character_reference
      @state = @return_state
    end
  end
end
