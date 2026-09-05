# htmlparser

A for-fun Ruby HTML parser that tries to be a **readable walk through the WHATWG
spec** — section numbers and step comments sit next to the code, not buried in a
native extension.

https://html.spec.whatwg.org/multipage/parsing.html

Scripting is **disabled** on purpose (`document.write`, `scripted_*` fixtures, and
friends are out of scope). Compliance claims mean: same tree the html5lib / WPT
corpora expect for non-scripted HTML.

## Spec scoreboard

Measured against [html5lib-tests](https://github.com/html5lib/html5lib-tests) and
WPT tree-construction fixtures (RSpec only — nothing from html5lib lands in
`lib/`).

| Gate | Result | Notes |
|------|--------|-------|
| Tokenizer (§13.2.5) | **pass** — 7032 / 7032 | |
| Tree dump (§13.2.6) | **pass*** — 1915 / 1922 | \*7 unclosed-EOF `<?…` cases: we emit the bogus comment the living spec requires; fixtures expect an empty body |
| Encoding sniff (§13.2.3) | **pass** — 82 / 82 | BOM + meta charset / http-equiv prescan |
| Serialize round-trip (§13.3) | **pass*** — 1659 / 1719 | \*60 known non-round-trips (plaintext, script text shaped like `</script>`, foster parenting, …) — normal HTML identity gaps, not missing serialize rules |
| Parse-error names (`#errors`) | **paused** — ~80% | Diagnostics only; not a correctness gate |

Also in the box: fragment parsing, foreign content (MathML/SVG), `to_html` /
`inner_html`, a small DOM surface (`get_element_by_id`, tag/class queries,
traversal), and a first-cut CSS selector engine (`query_selector` /
`query_selector_all` / `matches?` — type, id, class, attributes, and the usual
combinators).

## Setup

Ruby >= 3.4. Tokenizer fixtures are a **git submodule**:

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

Known residuals live under `spec/conformance/known_failures*.txt` (regenerate with
the matching `rake conformance:*:baseline` task).
