# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Tokenizer data and tags" do
  def tokens_of(html)
    tokenize(html).tokens
  end

  def chars_of(html)
    tokens_of(html).grep(HTMLParser::CharacterToken).map(&:value).join
  end

  it "emits character tokens and EOF for plain text" do
    result = tokens_of("Hi")
    expect(result[0]).to be_a(HTMLParser::CharacterToken)
    # Data state coalesces non-whitespace runs (html5lib-style).
    expect(result[0].value).to eq("Hi")
    expect(result.last).to be_a(HTMLParser::EOFToken)
  end

  it "emits a start tag" do
    tag = tokens_of("<div>").find { |t| t.is_a?(HTMLParser::StartTagToken) }
    expect(tag.name).to eq("div")
    expect(tag.self_closing).to eq(false)
  end

  it "emits an end tag" do
    tag = tokens_of("</div>").find { |t| t.is_a?(HTMLParser::EndTagToken) }
    expect(tag.name).to eq("div")
  end

  it "sets self-closing on start tags" do
    tag = tokens_of("<br/>").find { |t| t.is_a?(HTMLParser::StartTagToken) }
    expect(tag.name).to eq("br")
    expect(tag.self_closing).to eq(true)
  end

  it "emits comment tokens" do
    comment = tokens_of("<!--x-->").find { |t| t.is_a?(HTMLParser::CommentToken) }
    expect(comment.data).to eq("x")
  end

  it "resolves a simple named character reference" do
    expect(chars_of("&amp;")).to eq("&")
  end

  it "resolves a simple decimal character reference" do
    expect(chars_of("&#65;")).to eq("A")
  end

  it "resolves a hexadecimal character reference" do
    expect(chars_of("&#x41;")).to eq("A")
  end

  it "applies the numeric character-reference override table" do
    expect(chars_of("&#x80;")).to eq("\u20AC")
  end

  it "emits a lone ampersand when the character reference fails" do
    expect(chars_of("& ")).to eq("& ")
  end

  it "records a parse error for a missing semicolon after a named reference" do
    result = tokenize("&amp ")
    expect(result.parse_errors.map(&:code)).to include("missing-semicolon-after-character-reference")
    expect(result.tokens.grep(HTMLParser::CharacterToken).map(&:value).join).to eq("& ")
  end
end
