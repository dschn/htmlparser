# frozen_string_literal: true

module HTMLParser
  class StartTagToken
    attr_accessor :name, :attributes, :self_closing

    def initialize(name)
      @name = name
      @attributes = []
      @self_closing = false
    end
  end

  class EndTagToken
    attr_accessor :name, :attributes, :self_closing

    def initialize(name)
      @name = name
      @attributes = []
      @self_closing = false
    end
  end

  class CharacterToken
    attr_accessor :value

    def initialize(value)
      @value = value
    end
  end

  class DocTypeToken
    attr_accessor :name, :public_identifier, :system_identifier, :force_quirks

    def initialize(name = nil)
      @name = name
      @public_identifier = nil
      @system_identifier = nil
      @force_quirks = false
    end
  end

  class CommentToken
    attr_accessor :data

    def initialize(data)
      @data = data
    end
  end

  class EOFToken
    # End-of-file token (§13.2.5).
  end
end
