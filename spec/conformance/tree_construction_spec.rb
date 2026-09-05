# frozen_string_literal: true

require_relative "../support/html5lib_tree_construction"

RSpec.describe "html5lib/WPT tree-construction conformance" do
  fixtures_present = Dir.exist?(HTML5libTreeConstruction::FIXTURES_ROOT) &&
    !Dir[File.join(HTML5libTreeConstruction::FIXTURES_ROOT, "*.dat")].empty?

  before(:all) do
    unless fixtures_present
      skip "tree-construction fixtures missing under spec/fixtures/tree-construction"
    end
  end

  known_docs = HTML5libTreeConstruction.load_known_failures
  known_errors = HTML5libTreeConstruction.load_known_failures(
    HTML5libTreeConstruction::KNOWN_ERROR_FAILURES_PATH
  )

  HTML5libTreeConstruction.each_case do |test_case|
    it "#{test_case.file}[#{test_case.index}]: #{test_case.description}" do
      result = test_case.run
      doc_ok = test_case.document_matches?(result)
      err_ok = test_case.errors_match?(result)

      if known_docs.include?(test_case.key)
        if doc_ok
          raise "unexpected document pass — remove from known_failures_tree.txt:\n#{test_case.key}"
        end

        skip "known failure: #{result[:error] || "tree mismatch"}"
      end

      expect(result[:ok]).to eq(true), result[:error]
      expect(result[:document].to_s.rstrip).to eq(test_case.expected_document.to_s.rstrip)

      # `#errors` assertion only when the fixture has modern `(line,col): code` lines.
      next unless test_case.expected_errors.any?

      if known_errors.include?(test_case.key)
        if err_ok
          raise "unexpected #errors pass — remove from known_failures_tree_errors.txt:\n#{test_case.key}"
        end

        skip "known failure: #errors mismatch"
      end

      expect(test_case.errors_match?(result)).to eq(true), lambda {
        "expected: #{test_case.expected_errors.inspect}\n" \
          "  actual: #{result[:errors].inspect}"
      }
    end
  end
end
