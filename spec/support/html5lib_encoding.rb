# frozen_string_literal: true

# html5lib encoding .dat harness (§13.2.3 sniffing).
# Fixtures: spec/fixtures/html5lib/encoding/*.dat (binary-safe: #data may contain BOMs).
module HTML5libEncoding
  FIXTURES_ROOT = File.expand_path("../fixtures/html5lib/encoding", __dir__)
  KNOWN_FAILURES_PATH = File.expand_path("../conformance/known_failures_encoding.txt", __dir__)

  module_function

  def fixture_files
    Dir[File.join(FIXTURES_ROOT, "*.dat")].sort
  end

  def each_case
    fixture_files.each do |path|
      relative = File.basename(path)
      parse_dat(File.binread(path)).each_with_index do |raw, index|
        yield Case.new(
          file: relative,
          index: index,
          data: raw[:data],
          expected_encoding: raw[:encoding]
        )
      end
    end
  end

  # Binary .dat parser: `#data\n` … `\n#encoding\n` LABEL.
  def parse_dat(raw)
    cases = []
    raw.to_str.b.split("#data\n".b)[1..]&.each do |part|
      idx = part.index("\n#encoding\n".b)
      next unless idx

      data = part.byteslice(0, idx)
      rest = part.byteslice(idx + "\n#encoding\n".bytesize, part.bytesize)
      encoding = rest.to_s.split("\n", 2).first.to_s.strip
      next if encoding.empty?

      cases << {data: data, encoding: encoding}
    end
    cases
  end

  def known_failure_key(file:, index:, data:)
    preview = data.b.byteslice(0, 48).to_s.inspect
    "#{file}\t#{index}\t#{preview}"
  end

  def load_known_failures(path = KNOWN_FAILURES_PATH)
    return Set.new unless File.exist?(path)

    Set.new(File.readlines(path, chomp: true).reject { |l| l.empty? || l.start_with?("#") })
  end

  def write_known_failures(keys, path = KNOWN_FAILURES_PATH)
    File.write(path, keys.sort.map { |k| "#{k}\n" }.join)
  end

  class Case
    attr_reader :file, :index, :data, :expected_encoding

    def initialize(file:, index:, data:, expected_encoding:)
      @file = file
      @index = index
      @data = data
      @expected_encoding = expected_encoding
    end

    def key
      HTML5libEncoding.known_failure_key(file: file, index: index, data: data)
    end

    def description
      data.b.byteslice(0, 40).to_s.inspect
    end

    def run
      result = HTMLParser.sniff_encoding(data)
      {
        ok: true,
        encoding: result.name,
        confidence: result.confidence
      }
    rescue => e
      {ok: false, error: "#{e.class}: #{e.message}", encoding: nil}
    end

    def matches?(run_result)
      return false unless run_result[:ok]

      actual = HTMLParser::Encoding.get_encoding(run_result[:encoding])
      expected = HTMLParser::Encoding.get_encoding(expected_encoding)
      actual && expected && actual == expected
    end
  end
end
