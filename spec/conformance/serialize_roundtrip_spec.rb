# frozen_string_literal: true

require_relative "../support/html5lib_tree_construction"

# §13.3 property: parse → serialize → parse yields the same html5lib tree dump.
# Full documents only. Skips tree known-failures (wontfix dumps) and serialize residuals
# (plaintext / script end-tag-in-text / foster round-trips — HTML's known sharp edges).
SERIALIZE_ROUNDTRIP_KNOWN_PATH = File.expand_path("known_failures_serialize_roundtrip.txt", __dir__)

RSpec.describe "HTML serialize round-trip" do
  known_docs = HTML5libTreeConstruction.load_known_failures
  known_roundtrip = if File.exist?(SERIALIZE_ROUNDTRIP_KNOWN_PATH)
    Set.new(File.readlines(SERIALIZE_ROUNDTRIP_KNOWN_PATH, chomp: true).reject { |l| l.empty? || l.start_with?("#") })
  else
    Set.new
  end

  HTML5libTreeConstruction.each_case do |test_case|
    next unless test_case.document_fragment.nil?

    it "#{test_case.file}[#{test_case.index}]: round-trip #{test_case.description}" do
      if known_docs.include?(test_case.key)
        skip "known document dump failure"
      end

      first = HTMLParser.parse(test_case.data)
      unless test_case.document_matches?({ok: true, document: first.html5lib_dump})
        skip "first parse mismatch"
      end

      html = first.to_html
      second = HTMLParser.parse(html)
      passed = second.html5lib_dump.to_s.rstrip == first.html5lib_dump.to_s.rstrip

      if known_roundtrip.include?(test_case.key)
        if passed
          raise "unexpected round-trip pass — remove from known_failures_serialize_roundtrip.txt:\n#{test_case.key}"
        end
        skip "known serialize round-trip failure"
      end

      expect(second.html5lib_dump.to_s.rstrip).to eq(first.html5lib_dump.to_s.rstrip)
    end
  end
end
