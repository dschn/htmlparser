# frozen_string_literal: true

require_relative "../support/wpt_selectors"

# WPT Selectors-API Level 1 tables (dom/nodes/selectors.js) — document-context
# querySelectorAll + invalid selectors. See spec/fixtures/wpt/SOURCE.txt.
RSpec.describe "WPT selectors (document querySelector)" do
  known = WPTSelectors.load_known_failures

  WPTSelectors.each_case do |test_case|
    it "#{test_case.key}: #{test_case.description}" do
      result = test_case.run
      passed = test_case.matches?(result)

      if known.include?(test_case.key)
        if passed
          raise "unexpected pass — remove from known_failures_selectors.txt:\n#{test_case.key}"
        end
        skip "known selector failure"
      end

      expect(passed).to eq(true), failure_message(test_case, result)
    end
  end

  def failure_message(test_case, result)
    if test_case.is_a?(WPTSelectors::ValidCase)
      "selector=#{test_case.selector.inspect}\nexpected=#{test_case.expect.inspect}\n" \
        "actual=#{result[:ids].inspect}\nerror=#{result[:error].inspect}"
    else
      "expected SelectorError for #{test_case.selector.inspect}, got #{result.inspect}"
    end
  end
end
