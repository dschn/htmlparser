# frozen_string_literal: true

require_relative "tokens"
require_relative "parse_error"
require_relative "named_character_references"
require_relative "tokenizer/tag_states"
require_relative "tokenizer/content_model_states"
require_relative "tokenizer/script_data_states"
require_relative "tokenizer/comment_states"
require_relative "tokenizer/doctype_states"
require_relative "tokenizer/cdata_states"
require_relative "tokenizer/character_reference_states"

module HTMLParser
  class Tokenizer
    include TagStates
    include ContentModelStates
    include ScriptDataStates
    include CommentStates
    include DoctypeStates
    include CdataStates
    include CharacterReferenceStates

    EOF = nil
    NAMED_CHARACTER_REFERENCES = NamedCharacterReferences.load
    WHITESPACE = ["\u0009", "\u000a", "\u000c", "\u0020"].freeze
    PART_OF_AN_ATTRIBUTE = %i[
      attribute_value_double_quoted
      attribute_value_single_quoted
      attribute_value_unquoted
    ].freeze

    # §13.2.5.80 — legacy Windows-1252 overrides for C1 controls
    CHARACTER_REFERENCE_CODE_OVERRIDES = {
      0x80 => 0x20AC,
      0x82 => 0x201A,
      0x83 => 0x0192,
      0x84 => 0x201E,
      0x85 => 0x2026,
      0x86 => 0x2020,
      0x87 => 0x2021,
      0x88 => 0x02C6,
      0x89 => 0x2030,
      0x8A => 0x0160,
      0x8B => 0x2039,
      0x8C => 0x0152,
      0x8E => 0x017D,
      0x91 => 0x2018,
      0x92 => 0x2019,
      0x93 => 0x201C,
      0x94 => 0x201D,
      0x95 => 0x2022,
      0x96 => 0x2013,
      0x97 => 0x2014,
      0x98 => 0x02DC,
      0x99 => 0x2122,
      0x9A => 0x0161,
      0x9B => 0x203A,
      0x9C => 0x0153,
      0x9E => 0x017E,
      0x9F => 0x0178
    }.freeze

    # html5lib-style content model / initialStates → tokenizer state
    CONTENT_MODELS = {
      data: :data,
      rcdata: :rcdata,
      rawtext: :rawtext,
      script_data: :script_data,
      plaintext: :plaintext,
      cdata_section: :cdata_section
    }.freeze

    HTML5LIB_INITIAL_STATES = {
      "Data state" => :data,
      "PLAINTEXT state" => :plaintext,
      "RCDATA state" => :rcdata,
      "RAWTEXT state" => :rawtext,
      "Script data state" => :script_data,
      "CDATA section state" => :cdata_section
    }.freeze

    attr_reader :parse_errors, :state, :last_start_tag
    # Tree construction sets this so markup-declaration can enter CDATA in foreign content.
    attr_accessor :adjusted_current_node_provider

    def input_stream_line
      @input_stream.line
    end

    def input_stream_column
      @input_stream.column
    end

    def initialize(input_stream, content_model: :data, last_start_tag: nil, parse_errors: nil)
      @input_stream = input_stream
      @return_state = nil
      @state = CONTENT_MODELS.fetch(content_model) { content_model }
      @last_start_tag = last_start_tag&.downcase
      @current_tag_token = nil
      @comment_token = nil
      @temporary_buffer = +""
      @reconsume = false
      @tokens = Queue.new
      @parse_errors = parse_errors || []
      @halt = false
      @discard_attribute_value = false
      @skip_next_input_stream_error_report = false
      @adjusted_current_node_provider = nil
      @markup_line = 1
      @markup_column = 0
      @character_buffer = +""
      @character_buffer_line = nil
      @character_buffer_column = nil
    end

    def self.content_model_for_html5lib_state(name)
      HTML5LIB_INITIAL_STATES.fetch(name) do
        raise ArgumentError, "unknown html5lib initial state: #{name.inspect}"
      end
    end

    # §13.2.5 — appropriate end tag token: name matches the last start tag emitted.
    def appropriate_end_tag_token?(token = @current_tag_token)
      return false if @last_start_tag.nil? || token.nil?

      token.name == @last_start_tag
    end

    # Tree construction (and tests) may switch tokenizer state between tokens.
    def switch_to(state)
      @state = state
    end

    # html5lib data-state buffering: one CharacterToken per maximal run.
    def append_to_character_buffer(character)
      if @character_buffer.empty?
        @character_buffer_line = @input_stream.last_line
        @character_buffer_column = @input_stream.last_column
      end
      @character_buffer << character
    end

    def flush_character_buffer!
      return if @character_buffer.empty?

      token = CharacterToken.new(@character_buffer)
      token.line = @character_buffer_line
      token.column = @character_buffer_column
      @character_buffer = +""
      @character_buffer_line = nil
      @character_buffer_column = nil
      emit(token)
    end

    def parse
      @halt = false

      loop do
        parse_state_method = "parse_#{@state}_state"

        unless respond_to?(parse_state_method, true)
          raise HTMLParser::NotImplementedError, "unimp #{@state}"
        end

        send(parse_state_method)

        yield @tokens.pop until @tokens.empty?
        break if @halt
      end
    end

    private

    attr_reader :current_input_character

    def halt!
      @halt = true
    end

    def consume_next_input_character
      if @reconsume
        @reconsume = false
        return @current_input_character
      end

      @current_input_character = if @input_stream.eos?
        EOF
      else
        @input_stream.getch
      end
      report_input_stream_character_errors(@current_input_character)
      @current_input_character
    end

    # §13.2.3.5 — report when a character is first consumed (not on reconsume).
    # Returns true if an error was recorded. Callers that peek a character before a
    # tokenizer parse error (e.g. markup declaration open) may report early and set
    # @skip_next_input_stream_error_report so consume does not double-report.
    def report_input_stream_character_errors(char)
      return false if char.nil? # EOF

      if @skip_next_input_stream_error_report
        @skip_next_input_stream_error_report = false
        return false
      end

      code = char.unpack1("U")
      if code.between?(0xD800, 0xDFFF)
        parse_error("surrogate-in-input-stream")
      elsif noncharacter?(code)
        parse_error("noncharacter-in-input-stream")
      elsif control_character?(code)
        parse_error("control-character-in-input-stream")
      else
        return false
      end
      true
    end

    # Peek at the next character without consuming (spec "next input character").
    def next_input_character
      return @current_input_character if @reconsume
      return EOF if @input_stream.eos?

      @input_stream.peek(1)
    end

    # Spec "next N characters" — match only at the current position, then consume.
    def next_characters_are?(string, case_insensitive: false)
      peek = @input_stream.peek(string.length)
      return false if peek.nil? || peek.length < string.length

      case_insensitive ? peek.casecmp?(string) : (peek == string)
    end

    def consume_characters(count)
      count.times { @input_stream.getch }
    end

    def reconsume(state)
      @reconsume = true
      switch_to(state)
    end

    def return_to_and_switch_to(return_state, state)
      @return_state = return_state
      switch_to(state)
    end

    def switch_to_and_emit(state, token)
      switch_to(state)
      emit(token)
    end

    def emit(token)
      locate_emitted_token!(token)
      if token.is_a?(EndTagToken)
        parse_error("end-tag-with-attributes") unless token.attributes.empty?
        parse_error("end-tag-with-trailing-solidus") if token.self_closing
      elsif token.is_a?(StartTagToken)
        @last_start_tag = token.name
      end
      @tokens << token
    end

    # Record the `<` (or equivalent) that opened the current tag/comment/doctype.
    def note_markup_start!
      @markup_line = @input_stream.last_line
      @markup_column = @input_stream.last_column
    end

    def locate_new_token!(token)
      token.line = @markup_line
      token.column = @markup_column
      token
    end

    def locate_emitted_token!(token)
      return unless token.respond_to?(:line=)
      return if token.line

      if token.is_a?(CharacterToken) || token.is_a?(EOFToken)
        token.line = @input_stream.last_line
        token.column = @input_stream.last_column
      else
        locate_new_token!(token)
      end
    end

    def emit_eof!
      emit(EOFToken.new)
      halt!
    end

    def emit_eof_in_tag!
      parse_error("eof-in-tag")
      emit_eof!
    end

    def emit_eof_in_comment!
      parse_error("eof-in-comment")
      emit(@comment_token)
      emit_eof!
    end

    def emit_eof_in_doctype!
      parse_error("eof-in-doctype")
      @current_tag_token.force_quirks = true
      emit(@current_tag_token)
      emit_eof!
    end

    # After consuming the first character of a keyword (e.g. PUBLIC / SYSTEM).
    def match_from_current?(keyword)
      needed = keyword.length - 1
      peek = @input_stream.peek(needed) || ""
      return false if peek.length < needed

      (current_input_character + peek).casecmp?(keyword)
    end

    def consume_keyword_rest(keyword)
      consume_characters(keyword.length - 1)
    end

    def new_doctype_token(name = nil)
      @current_tag_token = locate_new_token!(DocTypeToken.new(name))
    end

    def append_replacement_to_attribute_name!
      parse_error("unexpected-null-character")
      @current_tag_token.attributes.last[:name] << "\ufffd"
    end

    def append_replacement_to_attribute_value!
      parse_error("unexpected-null-character")
      append_to_current_attribute_value!("\ufffd")
    end

    def append_to_current_attribute_value!(string)
      return if @discard_attribute_value

      @current_tag_token.attributes.last[:value] << string
    end

    # Codes where html5lib `#errors` report the next-character cursor (after the
    # triggering consume), matching `HTMLParser.stream.position()` in html5lib.
    # Most other tokenizer errors keep the bad character's last_* position.
    AFTER_CURSOR_PARSE_ERROR_CODES = %w[
      unexpected-null-character
      control-character-reference
      null-character-reference
      character-reference-outside-unicode-range
      surrogate-character-reference
      noncharacter-character-reference
      incorrectly-opened-comment
      abrupt-closing-of-empty-comment
      unknown-named-character-reference
      unexpected-character-in-attribute-name
      end-tag-with-attributes
    ].freeze

    NUMERIC_MISSING_SEMICOLON_STATES = %i[
      hexadecimal_character_reference
      decimal_character_reference
      numeric_character_reference_end
    ].freeze

    def parse_error(code)
      # EOF and selected codes use the post-consume cursor; others use the bad character.
      # Named missing-semicolon: after the entity match. Numeric: the terminating char.
      line, column = if use_after_cursor_for_parse_error?(code)
        [@input_stream.line, @input_stream.column]
      else
        [@input_stream.last_line, @input_stream.last_column]
      end
      @parse_errors << ParseError.new(
        code,
        line: line,
        column: column,
        tokenizer_state: @state
      )
    end

    def use_after_cursor_for_parse_error?(code)
      return true if @current_input_character == EOF
      return true if AFTER_CURSOR_PARSE_ERROR_CODES.include?(code)

      code == "missing-semicolon-after-character-reference" &&
        !NUMERIC_MISSING_SEMICOLON_STATES.include?(@state)
    end
    private :use_after_cursor_for_parse_error?

    def new_start_tag_token
      locate_new_token!(StartTagToken.new(+""))
    end

    def new_end_tag_token
      locate_new_token!(EndTagToken.new(+""))
    end

    def new_comment_token(data = +"")
      locate_new_token!(CommentToken.new(data))
    end

    def not_implemented(detail = nil)
      raise HTMLParser::NotImplementedError, detail
    end

    def consumed_as_part_of_an_attribute?
      PART_OF_AN_ATTRIBUTE.include?(@return_state)
    end

    def flush_code_points_consumed_as_character_reference
      # For each code point in the temporary buffer, append to the current
      # attribute's value if consumed as part of an attribute, or emit as a
      # character token otherwise.
      if consumed_as_part_of_an_attribute?
        append_to_current_attribute_value!(@temporary_buffer)
      else
        emit(CharacterToken.new(@temporary_buffer.dup))
      end
    end
  end
end
