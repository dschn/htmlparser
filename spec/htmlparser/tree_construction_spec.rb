# frozen_string_literal: true

require "spec_helper"

RSpec.describe HTMLParser::TreeConstruction do
  it "forwards tokens through process to the given block" do
    tokens = []
    HTMLParser.parse("Hi") { |token| tokens << token }

    expect(tokens.map(&:class)).to eq([
      HTMLParser::CharacterToken,
      HTMLParser::CharacterToken,
      HTMLParser::EOFToken
    ])
  end

  it "exposes an open elements stack" do
    expect(HTMLParser::OpenElements.new).to be_empty
  end

  it "builds a minimal document tree for plain text" do
    doc = HTMLParser.parse("Test") {}
    expect(doc.html5lib_dump).to eq(<<~DUMP.rstrip)
      | <html>
      |   <head>
      |   <body>
      |     "Test"
    DUMP
  end

  it "implies a second paragraph for consecutive p start tags" do
    doc = HTMLParser.parse("<p>One<p>Two") {}
    expect(doc.html5lib_dump).to eq(<<~DUMP.rstrip)
      | <html>
      |   <head>
      |   <body>
      |     <p>
      |       "One"
      |     <p>
      |       "Two"
    DUMP
  end

  it "foster-parents table characters and implies tbody/tr for bare td" do
    doc = HTMLParser.parse("<table>A<td>B</td>C</table>") {}
    expect(doc.html5lib_dump).to eq(<<~DUMP.rstrip)
      | <html>
      |   <head>
      |   <body>
      |     "AC"
      |     <table>
      |       <tbody>
      |         <tr>
      |           <td>
      |             "B"
    DUMP
  end

  it "runs the adoption agency for misnested anchor/paragraph" do
    doc = HTMLParser.parse("<a><p></a></p>") {}
    expect(doc.html5lib_dump).to eq(<<~DUMP.rstrip)
      | <html>
      |   <head>
      |   <body>
      |     <a>
      |     <p>
      |       <a>
    DUMP
  end

  it "puts template children under html5lib content" do
    doc = HTMLParser.parse("<template>Hello</template>") {}
    expect(doc.html5lib_dump).to eq(<<~DUMP.rstrip)
      | <html>
      |   <head>
      |     <template>
      |       content
      |         "Hello"
      |   <body>
    DUMP
  end
end
