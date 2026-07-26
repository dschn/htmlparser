# frozen_string_literal: true

require "spec_helper"

RSpec.describe HTMLParser::Input do
  describe ".normalize" do
    it "converts CRLF to LF" do
      expect(described_class.normalize("a\r\nb")).to eq("a\nb")
    end

    it "converts lone CR to LF" do
      expect(described_class.normalize("a\rb")).to eq("a\nb")
    end

    it "leaves LF alone" do
      expect(described_class.normalize("a\nb")).to eq("a\nb")
    end
  end
end
