# frozen_string_literal: true

require "spec_helper"

RSpec.describe HTMLParser::Encoding do
  describe ".decode" do
    it "decodes Windows-1252 bytes to UTF-8" do
      # 0x80 is EURO SIGN in windows-1252
      expect(described_class.decode("\x80".b, "windows-1252")).to eq("\u20AC")
    end

    it "decodes ISO-8859-2 bytes" do
      # 0xA1 is A OGONEK in iso-8859-2
      expect(described_class.decode("\xA1".b, "iso-8859-2")).to eq("\u0104")
    end

    it "strips a UTF-8 BOM then decodes" do
      expect(described_class.decode("\xEF\xBB\xBFhi".b, "utf-8")).to eq("hi")
    end

    it "replaces invalid UTF-8 with U+FFFD" do
      expect(described_class.decode("\xFF".b, "utf-8")).to eq("\uFFFD")
    end
  end

  describe ".encoding_from_meta_attributes" do
    it "reads charset" do
      attrs = [{name: "charset", value: "iso8859-2"}]
      expect(described_class.encoding_from_meta_attributes(attrs)).to eq("iso-8859-2")
    end

    it "reads http-equiv content-type charset" do
      attrs = [
        {name: "http-equiv", value: "Content-Type"},
        {name: "content", value: "text/html; charset=euc-jp"}
      ]
      expect(described_class.encoding_from_meta_attributes(attrs)).to eq("euc-jp")
    end
  end
end

RSpec.describe "HTMLParser.parse_bytes" do
  def title_text(doc)
    html = doc.children.find { |n| n.is_a?(HTMLParser::Element) && n.name == "html" }
    head = html.children.find { |n| n.is_a?(HTMLParser::Element) && n.name == "head" }
    title = head.children.find { |n| n.is_a?(HTMLParser::Element) && n.name == "title" }
    title.children.first.data
  end

  it "sniffs meta charset and decodes the document" do
    bytes = "<!DOCTYPE html><meta charset=iso8859-2><title>\xA1</title>".b
    doc = HTMLParser.parse_bytes(bytes)
    expect(doc.character_encoding).to eq("iso-8859-2")
    expect(title_text(doc)).to eq("\u0104")
  end

  it "treats a leading UTF-8 BOM as certain utf-8" do
    bytes = "\xEF\xBB\xBF<!DOCTYPE html><title>x</title>".b
    doc = HTMLParser.parse_bytes(bytes)
    expect(doc.character_encoding).to eq("utf-8")
    expect(doc.encoding_confidence).to eq(:certain)
  end

  it "reparses when a tentative encoding disagrees with meta" do
    # UTF-8 bytes for café; start as windows-1252 tentative so tree meta forces reparse.
    bytes = "<!DOCTYPE html><meta charset=utf-8><title>caf\xc3\xa9</title>".b
    doc = HTMLParser.parse_bytes(bytes, encoding: "windows-1252", confidence: :tentative)
    expect(doc.character_encoding).to eq("utf-8")
    expect(doc.encoding_confidence).to eq(:certain)
    expect(title_text(doc)).to eq("café")
  end

  it "does not reparse when confidence is already certain" do
    bytes = "<!DOCTYPE html><meta charset=utf-8><title>caf\xc3\xa9</title>".b
    doc = HTMLParser.parse_bytes(bytes, encoding: "windows-1252", confidence: :certain)
    expect(doc.character_encoding).to eq("windows-1252")
    # Misdecoded UTF-8 as windows-1252 — not "café"
    expect(title_text(doc)).not_to eq("café")
  end
end
