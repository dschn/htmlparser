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

  known = HTML5libTreeConstruction.load_known_failures

  HTML5libTreeConstruction.each_case do |test_case|
    it "#{test_case.file}[#{test_case.index}]: #{test_case.description}" do
      result = test_case.run
      passed = test_case.matches?(result)

      if known.include?(test_case.key)
        if passed
          raise "unexpected pass — remove from known_failures_tree.txt:\n#{test_case.key}"
        end

        skip "known failure: #{result[:error] || "tree mismatch"}"
      end

      expect(result[:ok]).to eq(true), result[:error]
      expect(result[:document].to_s.rstrip).to eq(test_case.expected_document.to_s.rstrip)
    end
  end
end
