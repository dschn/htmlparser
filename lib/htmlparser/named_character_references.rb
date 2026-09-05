# frozen_string_literal: true

require "json"

module HTMLParser
  # Longest-prefix lookup for named character references (§13.2.5.73).
  # Built once from `entities.json` as a character trie — replaces scanning every
  # entity name on each `&…` reference.
  class NamedCharacterReferences
    Match = Data.define(:name, :characters)

    def self.load(path = File.join(__dir__, "entities.json"))
      entities = JSON.parse(File.read(path))
      new.tap do |trie|
        entities.each do |key, value|
          trie.insert(key.delete_prefix("&"), value.fetch("characters"))
        end
      end
    end

    def initialize
      @root = Node.new
    end

    def insert(name, characters)
      node = @root
      name.each_char do |ch|
        node = node.child!(ch)
      end
      node.match = Match.new(name: name, characters: characters)
    end

    # Longest entity name that is a prefix of `chars[from..]`.
    # `chars` is an Array of single-character Strings (see InputStream).
    def longest_match(chars, from)
      node = @root
      best = nil
      i = from
      length = chars.length
      while i < length
        node = node[chars[i]]
        break unless node

        best = node.match if node.match
        i += 1
      end
      best
    end

    # Trie node: ASCII edge map + optional terminal Match.
    class Node
      attr_accessor :match

      def initialize
        @children = {}
        @match = nil
      end

      def [](ch)
        @children[ch]
      end

      def child!(ch)
        @children[ch] ||= Node.new
      end
    end
    private_constant :Node
  end
end
