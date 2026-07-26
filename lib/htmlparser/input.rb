# frozen_string_literal: true

module HTMLParser
  # §13.2.3.5 Preprocessing the input stream
  # https://html.spec.whatwg.org/multipage/parsing.html#preprocessing-the-input-stream
  #
  # The spec requires the input stream to be preprocessed before tokenization:
  # - Newlines: CRLF (U+000D U+000A) and CR (U+000D) must be converted to LF (U+000A).
  # - Encoding: the stream must be decoded (e.g. UTF-8); invalid bytes are replaced with
  #   U+FFFD REPLACEMENT CHARACTER per the Encoding Standard.
  #
  # Current implementation:
  # - Newline normalization is done (CRLF/CR → LF) as above.
  # - UTF-8 is decoded permissively so lone surrogates (written as 3-byte sequences by
  #   html5lib doubleEscaped fixtures via Array#pack("U")) remain as single code points.
  #   Surrogate / noncharacter / control-character-in-input-stream errors are reported
  #   when characters are first consumed (see Tokenizer#report_input_stream_character_errors).
  # - Full Encoding Standard / BOM / encoding sniffing not implemented yet.
  module Input
    def self.normalize(string)
      bytes = string.to_str.b
      bytes.gsub!("\r\n".b, "\n".b)
      bytes.tr!("\r".b, "\n".b)
      bytes
    end

    # Decode normalized bytes to Unicode code points, allowing surrogates.
    def self.codepoints(string)
      decode_utf8_allowing_surrogates(normalize(string))
    end

    def self.decode_utf8_allowing_surrogates(bytes)
      raw = bytes.bytes
      codes = []
      i = 0
      while i < raw.length
        b0 = raw[i]
        if b0 <= 0x7F
          codes.push(b0)
          i += 1
        elsif b0.between?(0xC2, 0xDF) && continuation?(raw, i + 1)
          codes.push(((b0 & 0x1F) << 6) | (raw[i + 1] & 0x3F))
          i += 2
        elsif b0.between?(0xE0, 0xEF) && continuation?(raw, i + 1) && continuation?(raw, i + 2)
          codes.push(
            ((b0 & 0x0F) << 12) | ((raw[i + 1] & 0x3F) << 6) | (raw[i + 2] & 0x3F)
          )
          i += 3
        elsif b0.between?(0xF0, 0xF4) && continuation?(raw, i + 1) &&
            continuation?(raw, i + 2) && continuation?(raw, i + 3)
          cp = ((b0 & 0x07) << 18) | ((raw[i + 1] & 0x3F) << 12) |
            ((raw[i + 2] & 0x3F) << 6) | (raw[i + 3] & 0x3F)
          codes.push((cp > 0x10FFFF) ? 0xFFFD : cp)
          i += 4
        else
          codes.push(0xFFFD)
          i += 1
        end
      end
      codes
    end

    def self.continuation?(raw, index)
      index < raw.length && (raw[index] & 0xC0) == 0x80
    end
    private_class_method :continuation?
  end

  # Character cursor over preprocessed input. Surrogate-safe alternative to StringScanner.
  class InputStream
    attr_reader :pos, :line, :column, :last_line, :last_column

    def initialize(string)
      @codepoints = Input.codepoints(string)
      @chars = @codepoints.map { |cp| [cp].pack("U") }
      @pos = 0
      # Position of the next character (html5lib: 1-based line, 0-based column).
      @line = 1
      @column = 0
      # Position of the character most recently returned by getch.
      @last_line = 1
      @last_column = 0
    end

    def eos?
      @pos >= @chars.length
    end

    def getch
      return nil if eos?

      @last_line = @line
      @last_column = @column
      ch = @chars[@pos]
      @pos += 1
      if ch == "\n"
        @line += 1
        @column = 0
      else
        @column += 1
      end
      ch
    end

    def peek(n = 1)
      return nil if eos?

      @chars[@pos, n]&.join
    end

    # Full remaining input including the character just before pos (for named char refs).
    def string_from(index)
      @chars[index..]&.join.to_s
    end

    def charpos
      @pos
    end

    attr_writer :pos
  end
end
