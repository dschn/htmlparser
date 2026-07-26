# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Tokenizer infrastructure" do
  it "exposes switch_to for tree construction feedback" do
    tokenizer = HTMLParser::Tokenizer.new(HTMLParser::InputStream.new(""))
    tokenizer.switch_to(:script_data)
    expect(tokenizer.state).to eq(:script_data)
  end

  it "accepts an initial content_model" do
    tokenizer = HTMLParser::Tokenizer.new(HTMLParser::InputStream.new(""), content_model: :data)
    expect(tokenizer.state).to eq(:data)
  end

  it "maps html5lib initial state names" do
    expect(HTMLParser::Tokenizer.content_model_for_html5lib_state("RCDATA state")).to eq(:rcdata)
  end

  it "records last_start_tag from emitted start tags" do
    tokenizer = HTMLParser::Tokenizer.new(HTMLParser::InputStream.new("<p>"), last_start_tag: "xmp")
    expect(tokenizer.last_start_tag).to eq("xmp")
    tokenizer.parse { |_t| }
    expect(tokenizer.last_start_tag).to eq("p")
  end

  it "raises NotImplementedError for unimplemented states" do
    tokenizer = HTMLParser::Tokenizer.new(HTMLParser::InputStream.new("x"), content_model: :bogus_made_up)
    expect { tokenizer.parse { nil } }.to raise_error(HTMLParser::NotImplementedError, /bogus_made_up/)
  end

  it "emits unexpected-null-character in the data state" do
    result = tokenize("\u0000")
    expect(result.tokens.first).to be_a(HTMLParser::CharacterToken)
    expect(result.tokens.first.value).to eq("\u0000")
    expect(result.parse_errors.map(&:code)).to include("unexpected-null-character")
  end

  it "emits control-character-in-input-stream for U+000B" do
    result = tokenize("\u000b")
    expect(result.parse_errors.map(&:code)).to eq(["control-character-in-input-stream"])
  end

  it "emits noncharacter-in-input-stream for U+FFFE" do
    result = tokenize("\ufffe")
    expect(result.parse_errors.map(&:code)).to eq(["noncharacter-in-input-stream"])
  end

  it "emits surrogate-in-input-stream and keeps the surrogate character" do
    surrogate = [0xD800].pack("U")
    result = tokenize(surrogate)
    expect(result.tokens.first.value).to eq(surrogate)
    expect(result.parse_errors.map(&:code)).to eq(["surrogate-in-input-stream"])
  end

  it "drops duplicate attributes and keeps the first value" do
    result = tokenize("<h a='b' a='d'>")
    tag = result.tokens.first
    expect(tag.attributes).to eq([{name: "a", value: "b"}])
    expect(result.parse_errors.map(&:code)).to include("duplicate-attribute")
  end
end
