# frozen_string_literal: true

module HTMLParser
  # §13.2.3 Determining the character encoding — label lookup + sniffing entry.
  # Labels follow the Encoding Standard (https://encoding.spec.whatwg.org/#names-and-labels).
  module Encoding
    SniffResult = Struct.new(:name, :confidence, keyword_init: true)

    # Subset of Encoding Standard labels → encoding name, enough for html5lib
    # encoding fixtures and common HTML declarations. Expand as needed.
    LABELS = {
      "unicode-1-1-utf-8" => "utf-8",
      "unicode11utf8" => "utf-8",
      "unicode20utf8" => "utf-8",
      "utf-8" => "utf-8",
      "utf8" => "utf-8",
      "x-unicode20utf8" => "utf-8",

      "utf-16be" => "utf-16be",
      "utf-16" => "utf-16le",
      "utf-16le" => "utf-16le",

      "chinese" => "gbk",
      "csgb2312" => "gbk",
      "csiso58gb231280" => "gbk",
      "gb2312" => "gbk",
      "gb_2312" => "gbk",
      "gb_2312-80" => "gbk",
      "gbk" => "gbk",
      "iso-ir-58" => "gbk",
      "x-gbk" => "gbk",

      "cseucpkdfmtjapanese" => "euc-jp",
      "euc-jp" => "euc-jp",
      "x-euc-jp" => "euc-jp",

      "csshiftjis" => "shift_jis",
      "ms932" => "shift_jis",
      "ms_kanji" => "shift_jis",
      "shift-jis" => "shift_jis",
      "shift_jis" => "shift_jis",
      "sjis" => "shift_jis",
      "windows-31j" => "shift_jis",
      "x-sjis" => "shift_jis",

      "cyrillic" => "windows-1251",
      "windows-1251" => "windows-1251",
      "x-cp1251" => "windows-1251",

      "ascii" => "windows-1252",
      "cp1252" => "windows-1252",
      "cp819" => "windows-1252",
      "csisolatin1" => "windows-1252",
      "ibm819" => "windows-1252",
      "iso-8859-1" => "windows-1252",
      "iso-ir-100" => "windows-1252",
      "iso8859-1" => "windows-1252",
      "iso88591" => "windows-1252",
      "iso_8859-1" => "windows-1252",
      "iso_8859-1:1987" => "windows-1252",
      "l1" => "windows-1252",
      "latin1" => "windows-1252",
      "us-ascii" => "windows-1252",
      "windows-1252" => "windows-1252",
      "x-cp1252" => "windows-1252",

      "csisolatin2" => "iso-8859-2",
      "iso-8859-2" => "iso-8859-2",
      "iso-ir-101" => "iso-8859-2",
      "iso8859-2" => "iso-8859-2",
      "iso88592" => "iso-8859-2",
      "iso_8859-2" => "iso-8859-2",
      "iso_8859-2:1987" => "iso-8859-2",
      "l2" => "iso-8859-2",
      "latin2" => "iso-8859-2"
    }.freeze

    module_function

    # Encoding Standard "get an encoding" for a label (ASCII case-insensitive).
    def get_encoding(label)
      return nil if label.nil?

      key = +label.to_s
      key.force_encoding(::Encoding::ISO_8859_1)
      key = key.encode(::Encoding::UTF_8).strip.downcase
      LABELS[key]
    rescue ::EncodingError
      nil
    end

    # §13.2.3 encoding sniffing algorithm (in-memory bytes; no transport/parent).
    # Returns a SniffResult. Confidence is :certain for BOM, else :tentative.
    def sniff(bytes, default: "windows-1252")
      data = bytes.to_str.b

      bom = sniff_bom(data)
      return SniffResult.new(name: bom, confidence: :certain) if bom

      from_meta = Prescan.encoding_from_meta(data)
      if from_meta
        # Meta UTF-16* is treated as UTF-8 (§13.2.3 / html5lib).
        from_meta = "utf-8" if from_meta.start_with?("utf-16")
        return SniffResult.new(name: from_meta, confidence: :tentative)
      end

      fallback = get_encoding(default) || "windows-1252"
      SniffResult.new(name: fallback, confidence: :tentative)
    end

    def sniff_bom(data)
      return "utf-8" if data.start_with?("\xEF\xBB\xBF".b)
      return "utf-32be" if data.start_with?("\x00\x00\xFE\xFF".b)
      return "utf-32le" if data.start_with?("\xFF\xFE\x00\x00".b)
      return "utf-16be" if data.start_with?("\xFE\xFF".b)
      return "utf-16le" if data.start_with?("\xFF\xFE".b)

      nil
    end
    private_class_method :sniff_bom

    # Encoding Standard name → Ruby Encoding name for String#encode.
    RUBY_NAMES = {
      "utf-8" => "UTF-8",
      "utf-16be" => "UTF-16BE",
      "utf-16le" => "UTF-16LE",
      "utf-32be" => "UTF-32BE",
      "utf-32le" => "UTF-32LE",
      "windows-1252" => "Windows-1252",
      "windows-1251" => "Windows-1251",
      "iso-8859-2" => "ISO-8859-2",
      "euc-jp" => "EUC-JP",
      "shift_jis" => "Windows-31J",
      "gbk" => "GBK"
    }.freeze

    # Decode `bytes` with Encoding Standard name → UTF-8 Ruby string (BOM stripped).
    # Invalid / undefined byte sequences become U+FFFD.
    def decode(bytes, name)
      data = bytes.to_str.b
      name = get_encoding(name) || name.to_s
      data = strip_bom(data, name)
      ruby_name = RUBY_NAMES.fetch(name) do
        raise ArgumentError, "unsupported encoding for decode: #{name.inspect}"
      end

      data.force_encoding(ruby_name)
      data.encode(
        ::Encoding::UTF_8,
        invalid: :replace,
        undef: :replace,
        replace: "\uFFFD"
      )
    end

    def strip_bom(data, name)
      case name
      when "utf-8"
        data.delete_prefix("\xEF\xBB\xBF".b)
      when "utf-16be"
        data.delete_prefix("\xFE\xFF".b)
      when "utf-16le"
        data.delete_prefix("\xFF\xFE".b)
      when "utf-32be"
        data.delete_prefix("\x00\x00\xFE\xFF".b)
      when "utf-32le"
        data.delete_prefix("\xFF\xFE\x00\x00".b)
      else
        data
      end
    end
    private_class_method :strip_bom

    # §13.2.6 — extracting a character encoding from a meta element's attributes.
    # `attrs` is an array of `{name:, value:}` (tokenizer attribute hashes).
    def encoding_from_meta_attributes(attrs)
      attrs = Array(attrs)
      charset = attrs.find { |a| a[:name].to_s.casecmp?("charset") }
      if charset
        enc = get_encoding(charset[:value])
        return enc
      end

      http_equiv = attrs.find { |a| a[:name].to_s.casecmp?("http-equiv") }
      content = attrs.find { |a| a[:name].to_s.casecmp?("content") }
      return nil unless http_equiv && content
      return nil unless http_equiv[:value].to_s.casecmp?("content-type")

      tentative = Prescan::ContentAttrParser.new(
        Prescan::Bytes.new(content[:value].to_s.b)
      ).parse
      get_encoding(tentative)
    end
  end

  # Raised from tree construction when §13.2.3.3 change-the-encoding must restart.
  class EncodingChanged < StandardError
    attr_reader :new_encoding

    def initialize(new_encoding)
      @new_encoding = new_encoding
      super("encoding changed to #{new_encoding}")
    end
  end
end
