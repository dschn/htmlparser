# frozen_string_literal: true

# Convenience runner from repo root. Prefer: ruby bin/htmlparser test [path]
# Usage: ruby run.rb [path]  (default path: test-html)
$LOAD_PATH.unshift(File.expand_path("lib", __dir__))
ARGV.unshift("test") if ARGV.first != "test"
load File.expand_path("bin/htmlparser", __dir__)
