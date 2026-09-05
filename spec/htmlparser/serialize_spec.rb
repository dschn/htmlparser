# frozen_string_literal: true

require "spec_helper"

RSpec.describe HTMLParser::Serialize do
  describe ".escape_string" do
    it "escapes text mode specials" do
      expect(described_class.escape_string('a&b<c>d"e', attribute_mode: false))
        .to eq("a&amp;b&lt;c&gt;d\"e")
    end

    it "escapes attribute mode specials including quotes" do
      expect(described_class.escape_string('a&b"c', attribute_mode: true))
        .to eq("a&amp;b&quot;c")
    end

    it "escapes CR as a numeric character reference" do
      expect(described_class.escape_string("a\rb", attribute_mode: false)).to eq("a&#13;b")
    end
  end

  describe "Document#to_html" do
    it "serializes a simple document" do
      doc = HTMLParser.parse("<!DOCTYPE html><p>Hi &amp; bye</p><br><img src=x>")
      html = doc.to_html
      expect(html).to include("<!DOCTYPE html>")
      expect(html).to include("<p>Hi &amp; bye</p>")
      expect(html).to include("<br>")
      expect(html).to include('<img src="x">')
      expect(html).not_to include("</br>")
      expect(html).not_to include("</img>")
    end

    it "does not escape script text" do
      doc = HTMLParser.parse("<!DOCTYPE html><script>if (a < b) {}</script>")
      expect(doc.to_html).to include("<script>if (a < b) {}</script>")
    end
  end

  describe "Element#outer_html / #inner_html" do
    it "distinguishes outer and inner" do
      doc = HTMLParser.parse("<!DOCTYPE html><div id=a><span>x</span></div>")
      div = doc.children.find { |n| n.is_a?(HTMLParser::Element) }
        .children.find { |n| n.name == "body" }
        .children.find { |n| n.name == "div" }
      expect(div.inner_html).to eq("<span>x</span>")
      expect(div.outer_html).to eq('<div id="a"><span>x</span></div>')
    end
  end
end
