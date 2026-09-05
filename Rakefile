# frozen_string_literal: true

require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

desc "Lint with Standard Ruby"
task :standard do
  sh "bundle exec standardrb"
end

namespace :conformance do
  desc "Run html5lib tokenizer conformance specs"
  RSpec::Core::RakeTask.new(:tokenizer) do |t|
    t.pattern = "spec/conformance/tokenizer_spec.rb"
  end

  namespace :tokenizer do
    desc "Rewrite known_failures.txt from current tokenizer mismatches"
    task :baseline do
      require_relative "lib/htmlparser"
      require_relative "spec/support/html5lib_tokenizer"

      failures = []
      HTML5libTokenizer.each_case do |test_case|
        result = test_case.run
        failures << test_case.key unless test_case.matches?(result)
      end

      HTML5libTokenizer.write_known_failures(failures)
      puts "Wrote #{failures.size} known failures to #{HTML5libTokenizer::KNOWN_FAILURES_PATH}"
    end
  end

  desc "Run html5lib/WPT tree-construction conformance specs"
  RSpec::Core::RakeTask.new(:tree) do |t|
    t.pattern = "spec/conformance/tree_construction_spec.rb"
  end

  namespace :tree do
    desc "Rewrite known_failures_tree{,_errors}.txt from current mismatches"
    task :baseline do
      require_relative "lib/htmlparser"
      require_relative "spec/support/html5lib_tree_construction"

      doc_failures = []
      error_failures = []
      HTML5libTreeConstruction.each_case do |test_case|
        result = test_case.run
        unless test_case.document_matches?(result)
          doc_failures << test_case.key
          next
        end
        error_failures << test_case.key unless test_case.errors_match?(result)
      end

      HTML5libTreeConstruction.write_known_failures(doc_failures)
      HTML5libTreeConstruction.write_known_error_failures(error_failures)
      puts "Wrote #{doc_failures.size} document failures to #{HTML5libTreeConstruction::KNOWN_FAILURES_PATH}"
      puts "Wrote #{error_failures.size} #errors failures to #{HTML5libTreeConstruction::KNOWN_ERROR_FAILURES_PATH}"
    end
  end

  desc "Run html5lib encoding sniffing conformance specs"
  RSpec::Core::RakeTask.new(:encoding) do |t|
    t.pattern = "spec/conformance/encoding_spec.rb"
  end

  namespace :encoding do
    desc "Rewrite known_failures_encoding.txt from current mismatches"
    task :baseline do
      require_relative "lib/htmlparser"
      require_relative "spec/support/html5lib_encoding"

      failures = []
      HTML5libEncoding.each_case do |test_case|
        result = test_case.run
        failures << test_case.key unless test_case.matches?(result)
      end

      HTML5libEncoding.write_known_failures(failures)
      puts "Wrote #{failures.size} known failures to #{HTML5libEncoding::KNOWN_FAILURES_PATH}"
    end
  end

  desc "Run HTML serialize round-trip property specs"
  RSpec::Core::RakeTask.new(:serialize) do |t|
    t.pattern = "spec/conformance/serialize_roundtrip_spec.rb"
  end
end

namespace :tokenizer do
  desc "List WHATWG tokenizer states vs implemented parse_*_state methods"
  task :status do
    require_relative "lib/htmlparser"

    # §13.2.5 state names (snake_case) — checklist for audits
    expected = %w[
      data rcdata rawtext script_data plaintext
      tag_open end_tag_open tag_name
      rcdata_less_than_sign rcdata_end_tag_open rcdata_end_tag_name
      rawtext_less_than_sign rawtext_end_tag_open rawtext_end_tag_name
      script_data_less_than_sign script_data_end_tag_open script_data_end_tag_name
      script_data_escape_start script_data_escape_start_dash script_data_escaped
      script_data_escaped_dash script_data_escaped_dash_dash
      script_data_escaped_less_than_sign script_data_escaped_end_tag_open
      script_data_escaped_end_tag_name script_data_double_escape_start
      script_data_double_escaped script_data_double_escaped_dash
      script_data_double_escaped_dash_dash script_data_double_escaped_less_than_sign
      script_data_double_escape_end
      before_attribute_name attribute_name after_attribute_name
      before_attribute_value attribute_value_double_quoted
      attribute_value_single_quoted attribute_value_unquoted
      after_attribute_value_quoted self_closing_start_tag
      bogus_comment markup_declaration_open
      comment_start comment_start_dash comment comment_less_than_sign
      comment_less_than_sign_bang comment_less_than_sign_bang_dash
      comment_less_than_sign_bang_dash_dash comment_end_dash comment_end comment_end_bang
      doctype before_doctype_name doctype_name after_doctype_name
      after_doctype_public_keyword before_doctype_public_identifier
      doctype_public_identifier_double_quoted doctype_public_identifier_single_quoted
      after_doctype_public_identifier between_doctype_public_and_system_identifiers
      after_doctype_system_keyword before_doctype_system_identifier
      doctype_system_identifier_double_quoted doctype_system_identifier_single_quoted
      after_doctype_system_identifier bogus_doctype
      cdata_section cdata_section_bracket cdata_section_end
      character_reference named_character_reference ambiguous_ampersand
      numeric_character_reference hexadecimal_character_reference_start
      decimal_character_reference_start hexadecimal_character_reference
      decimal_character_reference numeric_character_reference_end
    ].freeze

    implemented = HTMLParser::Tokenizer.instance_methods(false) +
      HTMLParser::Tokenizer.private_instance_methods(false)
    # Methods may live on included modules
    HTMLParser::Tokenizer.included_modules.each do |mod|
      next unless mod.name&.start_with?("HTMLParser::Tokenizer::")

      implemented.concat(mod.instance_methods(false))
    end
    implemented = implemented.map(&:to_s).grep(/\Aparse_.*_state\z/).map do |m|
      m.delete_prefix("parse_").delete_suffix("_state")
    end.uniq.sort

    expected_set = expected
    missing = expected_set - implemented
    extra = implemented - expected_set

    puts "Tokenizer states: #{implemented.size} implemented / #{expected_set.size} expected"
    puts
    puts "Implemented:"
    implemented.each { |s| puts "  ✓ #{s}" }
    puts
    puts "Missing:"
    missing.each { |s| puts "  ✗ #{s}" }
    unless extra.empty?
      puts
      puts "Extra (not in checklist):"
      extra.each { |s| puts "  ? #{s}" }
    end
  end
end
