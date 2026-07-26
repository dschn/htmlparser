# frozen_string_literal: true

require "spec_helper"

RSpec.describe HTMLParser::ParseError do
  it "stores the spec error code" do
    error = described_class.new("unexpected-null-character")
    expect(error.code).to eq("unexpected-null-character")
  end

  it "compares by code" do
    expect(described_class.new("eof-in-tag")).to eq(described_class.new("eof-in-tag"))
  end
end

RSpec.describe HTMLParser::NotImplementedError do
  it "includes detail in the message" do
    expect { raise described_class, "EOF" }.to raise_error(
      HTMLParser::NotImplementedError,
      /EOF/
    )
  end
end
