# frozen_string_literal: true

require_relative "lib/htmlparser/version"

Gem::Specification.new do |spec|
  spec.name = "htmlparser"
  spec.version = HTMLParser::VERSION
  spec.authors = ["Dustin Schneider"]
  spec.email = [""]

  spec.summary = "A spec-compliant HTML parser documenting the web spec"
  spec.description = "A non-serious spec-compliant HTML parser written in Ruby. See https://html.spec.whatwg.org/multipage/parsing.html"
  spec.homepage = "https://github.com/dschn/htmlparser"
  spec.license = "BSD-2-Clause"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*", "bin/*", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]
  spec.executables = ["htmlparser"]
end
