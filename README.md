# htmlparser

A non-serious, educational HTML parser in Ruby. It follows the WHATWG HTML
parsing algorithm with the spec’s steps documented alongside the code.

https://html.spec.whatwg.org/multipage/parsing.html

## Conformance

Compliance is measured against the shared html5lib / WPT fixture corpus used by
nearly every serious HTML5 / WHATWG implementation. We do **not** depend on the
html5lib Python library in `lib/`; fixtures drive RSpec only:

- **Tokenizer:** `spec/fixtures/html5lib` ([html5lib-tests](https://github.com/html5lib/html5lib-tests) submodule)
- **Tree construction:** `spec/fixtures/tree-construction` (`.dat` files from [WPT](https://github.com/web-platform-tests/wpt/tree/master/html/syntax/parsing/resources); see `SOURCE.txt`)

## Setup

Ruby >= 3.4. html5lib tokenizer fixtures are a **git submodule** — initialize them
before running the tokenizer suite (or clone with `--recurse-submodules`):

```bash
git submodule update --init
bundle install
```

## Running

```bash
bundle exec rspec
bundle exec standardrb
bundle exec rake tokenizer:status
bundle exec rake conformance:tokenizer
bundle exec rake conformance:tree
bundle exec htmlparser test path/to/file.html
```

Tokenizer suite is green (`known_failures.txt` empty). Tree-construction
mismatches live in `spec/conformance/known_failures_tree.txt` (regenerate with
`rake conformance:tree:baseline`).
