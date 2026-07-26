# frozen_string_literal: true

module TokenizeHelper
  def tokenize(html, content_model: :data, last_start_tag: nil)
    HTMLParser.tokenize(html, content_model: content_model, last_start_tag: last_start_tag)
  end
end

RSpec.configure do |config|
  config.include TokenizeHelper
end
