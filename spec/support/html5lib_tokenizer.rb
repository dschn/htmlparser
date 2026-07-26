# frozen_string_literal: true

require "json"

module HTML5libTokenizer
  FIXTURES_ROOT = File.expand_path("../fixtures/html5lib/tokenizer", __dir__)
  KNOWN_FAILURES_PATH = File.expand_path("../conformance/known_failures.txt", __dir__)

  # Skip infoset-coercion suite (not a pure HTML tokenizer concern).
  SKIP_FILES = %w[xmlViolation.test].freeze

  module_function

  def fixture_files
    Dir[File.join(FIXTURES_ROOT, "*.test")].sort.reject do |path|
      SKIP_FILES.include?(File.basename(path))
    end
  end

  def each_case
    fixture_files.each do |path|
      raw = File.read(path)
      data = JSON.parse(raw)
      tests = data["tests"] || data["xmlViolationTests"] || []
      relative = relative_fixture(path)

      tests.each do |test|
        states = test["initialStates"] || ["Data state"]
        states.each do |initial_state|
          yield Case.new(
            file: relative,
            description: test["description"],
            input: unescape_if_needed(test["input"], test["doubleEscaped"]),
            expected_output: unescape_output(test["output"], test["doubleEscaped"]),
            expected_errors: test["errors"],
            initial_state: initial_state,
            last_start_tag: test["lastStartTag"],
            double_escaped: test["doubleEscaped"]
          )
        end
      end
    end
  end

  def relative_fixture(path)
    path.delete_prefix("#{FIXTURES_ROOT}/")
  end

  def unescape_if_needed(string, double_escaped)
    return string unless double_escaped
    return string if string.nil?

    string.gsub(/\\u([0-9a-fA-F]{4})/) { [::Regexp.last_match(1).to_i(16)].pack("U") }
  end

  def unescape_output(output, double_escaped)
    return output unless double_escaped

    output.map { |token| unescape_token(token) }
  end

  def unescape_token(token)
    token.map do |part|
      case part
      when String
        unescape_if_needed(part, true)
      when Hash
        part.transform_values { |v| unescape_if_needed(v, true) }
      else
        part
      end
    end
  end

  def serialize_tokens(tokens)
    coalesced = []
    tokens.each do |token|
      next if token.is_a?(HTMLParser::EOFToken)

      serialized = serialize_token(token)
      if serialized[0] == "Character" && coalesced.last&.first == "Character"
        coalesced.last[1] = coalesced.last[1] + serialized[1]
      else
        coalesced << serialized
      end
    end
    coalesced
  end

  def serialize_token(token)
    case token
    when HTMLParser::DocTypeToken
      [
        "DOCTYPE",
        token.name,
        token.public_identifier,
        token.system_identifier,
        !token.force_quirks
      ]
    when HTMLParser::StartTagToken
      attrs = {}
      token.attributes.each { |a| attrs[a[:name]] = a[:value] }
      if token.self_closing
        ["StartTag", token.name, attrs, true]
      else
        ["StartTag", token.name, attrs]
      end
    when HTMLParser::EndTagToken
      ["EndTag", token.name]
    when HTMLParser::CommentToken
      ["Comment", token.data]
    when HTMLParser::CharacterToken
      ["Character", token.value]
    else
      raise "unknown token: #{token.class}"
    end
  end

  def error_codes(parse_errors)
    parse_errors.map(&:code)
  end

  def expected_error_codes(errors)
    return nil if errors.nil?

    errors.map { |e| e["code"] }
  end

  def known_failure_key(file:, description:, initial_state:)
    "#{file}\t#{description}\t#{initial_state}"
  end

  def load_known_failures(path = KNOWN_FAILURES_PATH)
    return Set.new unless File.exist?(path)

    Set.new(
      File.readlines(path, chomp: true).reject { |line| line.empty? || line.start_with?("#") }
    )
  end

  def write_known_failures(keys, path = KNOWN_FAILURES_PATH)
    header = <<~HEADER
      # html5lib tokenizer known failures — regenerate with:
      #   bundle exec rake conformance:tokenizer:baseline
      # Format: relative_file<TAB>description<TAB>initial_state
    HEADER
    body = keys.sort.map { |k| "#{k}\n" }.join
    File.write(path, header + body)
  end

  class Case
    attr_reader :file, :description, :input, :expected_output, :expected_errors,
      :initial_state, :last_start_tag, :double_escaped

    def initialize(file:, description:, input:, expected_output:, expected_errors:,
      initial_state:, last_start_tag:, double_escaped:)
      @file = file
      @description = description
      @input = input
      @expected_output = expected_output
      @expected_errors = expected_errors
      @initial_state = initial_state
      @last_start_tag = last_start_tag
      @double_escaped = double_escaped
    end

    def key
      HTML5libTokenizer.known_failure_key(
        file: file,
        description: description,
        initial_state: initial_state
      )
    end

    def content_model
      HTMLParser::Tokenizer.content_model_for_html5lib_state(initial_state)
    end

    def run
      result = HTMLParser.tokenize(
        input,
        content_model: content_model,
        last_start_tag: last_start_tag
      )
      {
        ok: true,
        output: HTML5libTokenizer.serialize_tokens(result.tokens),
        errors: HTML5libTokenizer.error_codes(result.parse_errors)
      }
    rescue HTMLParser::NotImplementedError, StandardError => e
      {
        ok: false,
        error: "#{e.class}: #{e.message}",
        output: nil,
        errors: nil
      }
    end

    def matches?(run_result)
      return false unless run_result[:ok]
      return false unless run_result[:output] == expected_output

      expected_codes = HTML5libTokenizer.expected_error_codes(expected_errors)
      return true if expected_codes.nil?

      run_result[:errors] == expected_codes
    end
  end
end
