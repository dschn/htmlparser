# frozen_string_literal: true

# html5lib / WPT tree-construction .dat harness.
# Fixtures: spec/fixtures/tree-construction/*.dat (from WPT; see SOURCE.txt).
module HTML5libTreeConstruction
  FIXTURES_ROOT = File.expand_path("../fixtures/tree-construction", __dir__)
  KNOWN_FAILURES_PATH = File.expand_path("../conformance/known_failures_tree.txt", __dir__)

  module_function

  def fixture_files
    Dir[File.join(FIXTURES_ROOT, "*.dat")].sort.reject do |path|
      # scripted_*.dat require JS; skipped while targeting scripting disabled.
      File.basename(path).start_with?("scripted_")
    end
  end

  def each_case
    fixture_files.each do |path|
      relative = File.basename(path)
      parse_dat(File.read(path)).each_with_index do |raw, index|
        next if raw[:scripting] == true # scripting-disabled target

        yield Case.new(
          file: relative,
          index: index,
          data: raw[:data],
          errors: raw[:errors],
          new_errors: raw[:new_errors],
          document_fragment: raw[:document_fragment],
          expected_document: raw[:document],
          scripting: raw[:scripting]
        )
      end
    end
  end

  def parse_dat(contents)
    tests = []
    current = new_raw_test
    section = nil

    contents.each_line do |line|
      line = line.chomp
      case line
      when "#data"
        tests << current unless current[:data].nil?
        current = new_raw_test
        section = :data
      when "#errors"
        current[:data] = +"" if current[:data].nil? && section == :data
        section = :errors
      when "#new-errors"
        section = :new_errors
      when "#document-fragment"
        current[:data] = +"" if current[:data].nil? && section == :data
        section = :document_fragment
      when "#document"
        current[:data] = +"" if current[:data].nil? && section == :data
        section = :document
      when "#script-on"
        current[:scripting] = true
        section = nil
      when "#script-off"
        current[:scripting] = false
        section = nil
      else
        next if section.nil?

        case section
        when :data
          current[:data] = current[:data] ? "#{current[:data]}\n#{line}" : +line
        when :errors
          current[:errors] << line unless line.empty?
        when :new_errors
          current[:new_errors] << line unless line.empty?
        when :document_fragment
          current[:document_fragment] = line
        when :document
          current[:document] = current[:document] ? "#{current[:document]}\n#{line}" : +line
        end
      end
    end
    tests << current unless current[:data].nil?
    tests
  end

  def new_raw_test
    {
      data: nil,
      errors: [],
      new_errors: [],
      document_fragment: nil,
      document: nil,
      scripting: false
    }
  end

  def known_failure_key(file:, index:, data:)
    snippet = data.to_s.gsub(/\s+/, " ").slice(0, 80)
    "#{file}\t#{index}\t#{snippet}"
  end

  def load_known_failures(path = KNOWN_FAILURES_PATH)
    return Set.new unless File.exist?(path)

    Set.new(
      File.readlines(path, chomp: true).reject { |line| line.empty? || line.start_with?("#") }
    )
  end

  def write_known_failures(keys, path = KNOWN_FAILURES_PATH)
    header = <<~HEADER
      # html5lib/WPT tree-construction known failures — regenerate with:
      #   bundle exec rake conformance:tree:baseline
      # Format: file<TAB>index<TAB>data_snippet
    HEADER
    body = keys.sort.map { |k| "#{k}\n" }.join
    File.write(path, header + body)
  end

  class Case
    attr_reader :file, :index, :data, :errors, :new_errors, :document_fragment,
      :expected_document, :scripting

    def initialize(file:, index:, data:, errors:, new_errors:, document_fragment:,
      expected_document:, scripting:)
      @file = file
      @index = index
      @data = data
      @errors = errors
      @new_errors = new_errors
      @document_fragment = document_fragment
      @expected_document = expected_document.to_s
      @scripting = scripting
    end

    def key
      HTML5libTreeConstruction.known_failure_key(file: file, index: index, data: data)
    end

    def fragment?
      !document_fragment.nil?
    end

    def description
      snippet = data.to_s.gsub(/\s+/, " ").slice(0, 60)
      fragment? ? "#{snippet} (fragment #{document_fragment})" : snippet
    end

    def run
      if fragment?
        return {
          ok: false,
          error: "fragment parsing not implemented",
          document: nil
        }
      end

      document = HTMLParser.parse(data) { |_token| }
      {
        ok: true,
        document: HTML5libTreeConstruction.serialize_document(document),
        error: nil
      }
    rescue HTMLParser::NotImplementedError, StandardError => e
      {
        ok: false,
        error: "#{e.class}: #{e.message}",
        document: nil
      }
    end

    def matches?(run_result)
      return false unless run_result[:ok]

      run_result[:document].to_s.rstrip == expected_document.to_s.rstrip
    end
  end

  # Serialize our DOM to html5lib tree dump. Grows with Document/Element APIs.
  def serialize_document(document)
    return "" if document.nil?
    return "" unless document.respond_to?(:html5lib_dump)

    document.html5lib_dump
  end
end
