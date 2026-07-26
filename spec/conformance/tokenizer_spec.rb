# frozen_string_literal: true

require_relative "../support/html5lib_tokenizer"

RSpec.describe "html5lib tokenizer conformance" do
  fixtures_present = Dir.exist?(HTML5libTokenizer::FIXTURES_ROOT) &&
    !Dir[File.join(HTML5libTokenizer::FIXTURES_ROOT, "*.test")].empty?

  before(:all) do
    unless fixtures_present
      skip "html5lib fixtures missing — run: git submodule update --init"
    end
  end

  known = HTML5libTokenizer.load_known_failures

  HTML5libTokenizer.each_case do |test_case|
    it "#{test_case.file}: #{test_case.description} (#{test_case.initial_state})" do
      result = test_case.run
      passed = test_case.matches?(result)

      if known.include?(test_case.key)
        if passed
          raise "unexpected pass — remove from known_failures.txt:\n#{test_case.key}"
        end

        skip "known failure: #{result[:error] || "token/error mismatch"}"
      end

      expect(result[:ok]).to eq(true), result[:error]
      expect(result[:output]).to eq(test_case.expected_output)
      expected_codes = HTML5libTokenizer.expected_error_codes(test_case.expected_errors)
      expect(result[:errors]).to eq(expected_codes) if expected_codes
    end
  end
end
