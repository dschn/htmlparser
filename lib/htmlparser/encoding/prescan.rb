# frozen_string_literal: true

module HTMLParser
  module Encoding
    # §13.2.3.2 Prescan a byte stream to determine its encoding.
    # Byte-oriented mini-parser (html5lib EncodingParser shape), ASCII-lowercasing
    # the buffer so attribute matching is case-insensitive.
    module Prescan
      SPACE = " \t\n\f\r".b.freeze
      SPACE_SLASH = " \t\n\f\r/".b.freeze
      SPACES_ANGLE = " \t\n\f\r<>".b.freeze

      module_function

      def encoding_from_meta(bytes)
        Parser.new(bytes.to_str.b).encoding
      end

      # Mutable cursor over a lowercased ASCII-compatible byte string.
      class Bytes
        attr_reader :bytes
        attr_accessor :position

        def initialize(raw)
          @bytes = raw.downcase
          @position = 0
        end

        def length
          @bytes.bytesize
        end

        def [](range)
          @bytes[range]
        end

        def current_byte
          return nil if @position.nil? || @position < 0 || @position >= length

          @bytes[@position, 1]
        end

        def advance!
          @position += 1
          raise StopIteration if @position >= length

          current_byte
        end

        def retreat!
          raise StopIteration if @position >= length

          @position -= 1
          current_byte
        end

        def skip(chars = SPACE)
          p = [@position, 0].max
          while p < length
            c = @bytes[p, 1]
            unless chars.include?(c)
              @position = p
              return c
            end
            p += 1
          end
          @position = p
          nil
        end

        def skip_until(chars)
          p = [@position, 0].max
          while p < length
            c = @bytes[p, 1]
            if chars.include?(c)
              @position = p
              return c
            end
            p += 1
          end
          @position = p
          nil
        end

        def match_bytes?(prefix)
          p = [@position, 0].max
          return false unless @bytes.byteslice(p, prefix.bytesize) == prefix

          @position = p + prefix.bytesize
          true
        end

        def jump_to(needle)
          p = [@position, 0].max
          idx = @bytes.index(needle, p)
          raise StopIteration unless idx

          @position = idx + needle.bytesize - 1
          true
        end

        def include?(needle)
          @bytes.include?(needle)
        end
      end

      class Parser
        def initialize(raw)
          @data = Bytes.new(raw)
          @encoding = nil
          @computed = false
        end

        def encoding
          return @encoding if @computed

          @computed = true
          return nil unless @data.include?("<meta".b)

          loop do
            begin
              @data.jump_to("<".b)
            rescue StopIteration
              break
            end

            keep = true
            begin
              if @data.match_bytes?("<!--".b)
                keep = handle_comment
              elsif @data.match_bytes?("<meta".b)
                keep = handle_meta
              elsif @data.match_bytes?("</".b)
                keep = handle_possible_end_tag
              elsif @data.match_bytes?("<!".b) || @data.match_bytes?("<?".b)
                keep = handle_other
              elsif @data.match_bytes?("<".b)
                keep = handle_possible_start_tag
              end
            rescue StopIteration
              keep = false
            end
            break unless keep
          end

          @encoding
        end

        private

        def handle_comment
          @data.jump_to("-->".b)
        end

        def handle_meta
          c = @data.current_byte
          return true unless c && SPACE.include?(c)

          has_pragma = false
          pending = nil
          loop do
            attr = get_attribute
            return true if attr.nil?

            name, value = attr
            case name
            when "http-equiv".b
              has_pragma = (value == "content-type".b)
              if has_pragma && pending
                @encoding = pending
                return false
              end
            when "charset".b
              codec = HTMLParser::Encoding.get_encoding(value)
              if codec
                @encoding = codec
                return false
              end
            when "content".b
              tentative = ContentAttrParser.new(Bytes.new(value)).parse
              next unless tentative

              codec = HTMLParser::Encoding.get_encoding(tentative)
              next unless codec

              if has_pragma
                @encoding = codec
                return false
              end
              pending = codec
            end
          end
        end

        def handle_possible_start_tag
          handle_possible_tag(false)
        end

        def handle_possible_end_tag
          @data.advance!
          handle_possible_tag(true)
        end

        def handle_possible_tag(end_tag)
          c = @data.current_byte
          unless c&.match?(/[a-z]/)
            if end_tag
              @data.retreat!
              handle_other
            end
            return true
          end

          c = @data.skip_until(SPACES_ANGLE)
          if c == "<".b
            @data.retreat!
          else
            attr = get_attribute
            attr = get_attribute while attr
          end
          true
        end

        def handle_other
          @data.jump_to(">".b)
        end

        # §13.2.3.2 — get an attribute
        def get_attribute
          data = @data
          c = data.skip(SPACE_SLASH)
          return nil if c.nil? || c == ">".b

          attr_name = +"".b
          attr_value = +"".b

          loop do
            if c == "=".b && !attr_name.empty?
              break
            elsif SPACE.include?(c)
              c = data.skip
              break
            elsif c == "/".b || c == ">".b
              return [attr_name, "".b]
            elsif c.nil?
              return nil
            else
              attr_name << c
            end
            c = data.advance!
          end

          if c != "=".b
            data.retreat!
            return [attr_name, "".b]
          end

          data.advance!
          c = data.skip
          if c == "'".b || c == '"'.b
            quote = c
            loop do
              c = data.advance!
              if c == quote
                data.advance!
                return [attr_name, attr_value]
              elsif c.nil?
                return nil
              else
                attr_value << c
              end
            end
          elsif c == ">".b
            return [attr_name, "".b]
          elsif c.nil?
            return nil
          else
            attr_value << c
          end

          loop do
            c = data.advance!
            if c.nil?
              return nil
            elsif SPACES_ANGLE.include?(c)
              return [attr_name, attr_value]
            else
              attr_value << c
            end
          end
        end
      end

      # Extract charset=… from a meta content attribute value.
      class ContentAttrParser
        def initialize(data)
          @data = data
        end

        def parse
          @data.jump_to("charset".b)
          @data.position += 1
          @data.skip
          return nil unless @data.current_byte == "=".b

          @data.position += 1
          @data.skip
          if @data.current_byte == '"'.b || @data.current_byte == "'".b
            quote = @data.current_byte
            @data.position += 1
            start = @data.position
            return nil unless @data.jump_to(quote)

            @data[start...@data.position]
          else
            start = @data.position
            begin
              @data.skip_until(SPACE)
              @data[start...@data.position]
            rescue StopIteration
              @data[start..]
            end
          end
        rescue StopIteration
          nil
        end
      end
    end
  end
end
