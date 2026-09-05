# frozen_string_literal: true

require "json"

# WPT Selectors-API tables (dom/nodes/selectors.js) against our querySelector.
# Document-context QSA + invalid-selector SyntaxError checks.
# Fixtures: spec/fixtures/wpt/dom/nodes/{selectors.json,ParentNode-querySelector-All-content.html}
module WPTSelectors
  FIXTURES_ROOT = File.expand_path("../fixtures/wpt/dom/nodes", __dir__)
  SELECTORS_JSON = File.join(FIXTURES_ROOT, "selectors.json")
  CONTENT_HTML = File.join(FIXTURES_ROOT, "ParentNode-querySelector-All-content.html")
  KNOWN_FAILURES_PATH = File.expand_path("../conformance/known_failures_selectors.txt", __dir__)

  TEST_QSA = 0x01

  module_function

  def data
    @data ||= JSON.parse(File.read(SELECTORS_JSON))
  end

  def document
    @document ||= ::HTMLParser.parse(File.read(CONTENT_HTML))
  end

  def load_known_failures
    return Set.new unless File.exist?(KNOWN_FAILURES_PATH)

    Set.new(File.readlines(KNOWN_FAILURES_PATH, chomp: true).reject { |l| l.empty? || l.start_with?("#") })
  end

  def write_known_failures(keys)
    File.write(
      KNOWN_FAILURES_PATH,
      <<~HEADER + keys.sort.map { |k| "#{k}\n" }.join
        # WPT selectors.js known failures — regenerate with:
        #   bundle exec rake conformance:selectors:baseline
        # Format: kind<TAB>index<TAB>selector_snippet
      HEADER
    )
  end

  def each_case
    each_invalid_case { |c| yield c }
    each_valid_document_case { |c| yield c }
  end

  def each_invalid_case
    data.fetch("invalidSelectors").each_with_index do |raw, index|
      yield InvalidCase.new(index: index, name: raw.fetch("name"), selector: raw.fetch("selector"))
    end
  end

  def each_valid_document_case
    data.fetch("validSelectors").each_with_index do |raw, index|
      test_type = raw.fetch("testType")
      next if (test_type & TEST_QSA).zero?

      exclude = Array(raw["exclude"])
      next if exclude.include?("document") || exclude.include?("html")

      yield ValidCase.new(
        index: index,
        name: raw.fetch("name"),
        selector: raw.fetch("selector"),
        expect: Array(raw["expect"]),
        context: :document
      )
    end
  end

  class InvalidCase
    attr_reader :index, :name, :selector

    def initialize(index:, name:, selector:)
      @index = index
      @name = name
      @selector = selector
    end

    def key
      "invalid\t#{index}\t#{selector[0, 60].inspect}"
    end

    def description
      "#{name}: #{selector.inspect}"
    end

    def run
      document.query_selector(selector)
      {ok: false, error: nil}
    rescue ::HTMLParser::SelectorError => e
      {ok: true, error: e}
    rescue => e
      {ok: false, error: e}
    end

    def matches?(result)
      result[:ok]
    end

    def document
      WPTSelectors.document
    end
  end

  class ValidCase
    attr_reader :index, :name, :selector, :expect, :context

    def initialize(index:, name:, selector:, expect:, context:)
      @index = index
      @name = name
      @selector = selector
      @expect = expect
      @context = context
    end

    def key
      "valid\t#{index}\t#{selector[0, 60].inspect}"
    end

    def description
      "#{name}: #{selector.inspect}"
    end

    def run
      ids = root.query_selector_all(selector).map { |el| el.id.to_s }
      {ok: true, ids: ids, error: nil}
    rescue ::HTMLParser::SelectorError, StandardError => e
      {ok: false, ids: nil, error: e}
    end

    def matches?(result)
      result[:ok] && result[:ids] == expect
    end

    def root
      WPTSelectors.document
    end
  end
end
