# frozen_string_literal: true

module HTMLParser
  # Source location for html5lib `#errors` (1-based line, 0-based column).
  module TokenLocation
    attr_accessor :line, :column
  end

  class StartTagToken
    include TokenLocation

    attr_accessor :name, :attributes, :self_closing

    def initialize(name)
      @name = name
      @attributes = []
      @self_closing = false
    end
  end

  class EndTagToken
    include TokenLocation

    attr_accessor :name, :attributes, :self_closing

    def initialize(name)
      @name = name
      @attributes = []
      @self_closing = false
    end
  end

  class CharacterToken
    include TokenLocation

    attr_accessor :value

    def initialize(value)
      @value = value
    end
  end

  class DocTypeToken
    include TokenLocation

    attr_accessor :name, :public_identifier, :system_identifier, :force_quirks

    def initialize(name = nil)
      @name = name
      @public_identifier = nil
      @system_identifier = nil
      @force_quirks = false
    end
  end

  class CommentToken
    include TokenLocation

    attr_accessor :data

    def initialize(data)
      @data = data
    end
  end

  class EOFToken
    include TokenLocation

    # End-of-file token (§13.2.5).
  end
end
