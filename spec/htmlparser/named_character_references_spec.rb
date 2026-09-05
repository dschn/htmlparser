# frozen_string_literal: true

require "spec_helper"

RSpec.describe HTMLParser::NamedCharacterReferences do
  subject(:trie) { described_class.load }

  it "matches the longest entity prefix" do
    chars = HTMLParser::InputStream.new("CounterClockwiseContourIntegral;x").chars
    match = trie.longest_match(chars, 0)
    expect(match.name).to eq("CounterClockwiseContourIntegral;")
    expect(match.characters).to eq("∳")
  end

  it "prefers a semicolon form when both exist" do
    chars = HTMLParser::InputStream.new("amp;").chars
    expect(trie.longest_match(chars, 0).name).to eq("amp;")
  end

  it "still matches legacy names without a semicolon" do
    chars = HTMLParser::InputStream.new("amp ").chars
    expect(trie.longest_match(chars, 0).name).to eq("amp")
  end

  it "returns nil when nothing matches" do
    chars = HTMLParser::InputStream.new("xyzzy;").chars
    expect(trie.longest_match(chars, 0)).to be_nil
  end
end
