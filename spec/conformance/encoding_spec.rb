# frozen_string_literal: true

require_relative "../support/html5lib_encoding"

RSpec.describe "html5lib encoding sniffing conformance" do
  fixtures_present = Dir.exist?(HTML5libEncoding::FIXTURES_ROOT) &&
    !Dir[File.join(HTML5libEncoding::FIXTURES_ROOT, "*.dat")].empty?

  before(:all) do
    unless fixtures_present
      skip "encoding fixtures missing under spec/fixtures/html5lib/encoding"
    end
  end

  known = HTML5libEncoding.load_known_failures

  HTML5libEncoding.each_case do |test_case|
    it "#{test_case.file}[#{test_case.index}]: #{test_case.description}" do
      result = test_case.run
      passed = test_case.matches?(result)

      if known.include?(test_case.key)
        if passed
          raise "unexpected encoding pass — remove from known_failures_encoding.txt:\n#{test_case.key}"
        end

        skip "known failure: #{result[:error] || "encoding mismatch (#{result[:encoding]})"}"
      end

      expect(result[:ok]).to eq(true), result[:error]
      expect(test_case.matches?(result)).to eq(true), lambda {
        "expected: #{test_case.expected_encoding.inspect}\n" \
          "  actual: #{result[:encoding].inspect}"
      }
    end
  end
end
