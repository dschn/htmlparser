# frozen_string_literal: true

module HTMLParser
  # 13.2.3.5 Preprocessing the input stream
  # https://html.spec.whatwg.org/multipage/parsing.html#preprocessing-the-input-stream
  #
  # The spec requires the input stream to be preprocessed before tokenization:
  # - Newlines: CRLF (U+000D U+000A) and CR (U+000D) must be converted to LF (U+000A).
  # - Encoding: the stream must be decoded (e.g. UTF-8); invalid bytes are replaced with
  #   U+FFFD REPLACEMENT CHARACTER per the Encoding Standard.
  #
  # Current implementation:
  # - Newline normalization is done (CRLF/CR → LF) as above.
  # - Encoding: we use String#scrub as a stand-in only. That replaces invalid UTF-8
  #   sequences with the default replacement character, but the spec has more to say
  #   (BOM handling, explicit encoding detection, etc.). So this is a known gap:
  #   "utf-8 jank" / incomplete preprocessing. When picking this back up, implement
  #   full preprocessing per 13.2.3.5 and the Encoding Standard so the parser is
  #   spec-compliant for arbitrary byte streams (files, network, etc.).
  module Input
    def self.normalize(string)
      string = string.scrub
      string.gsub(/\u000d\u000a/, "\u000a").gsub("\u000d", "\u000a")
    end
  end
end
