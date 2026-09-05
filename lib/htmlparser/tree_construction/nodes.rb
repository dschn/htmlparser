# frozen_string_literal: true

module HTMLParser
  HTML_NAMESPACE = "http://www.w3.org/1999/xhtml"

  # Minimal DOM nodes for §13.2.6 tree construction + html5lib dump serialization.
  class Node
    attr_accessor :parent
    attr_reader :children

    def initialize
      @parent = nil
      @children = []
    end

    def append_child(node)
      node.parent&.remove_child(node) if node.parent && node.parent != self
      node.parent = self
      @children << node
      node
    end

    def insert_before(node, sibling)
      node.parent&.remove_child(node) if node.parent && node.parent != self
      idx = @children.index(sibling)
      if idx
        node.parent = self
        @children.insert(idx, node)
      else
        append_child(node)
      end
      node
    end

    def remove_child(node)
      @children.delete(node)
      node.parent = nil
      node
    end
  end

  InsertionLocation = Struct.new(:parent, :before)

  # DocumentFragment used as a template element's template contents (§4.12.3 / §13.2.6).
  class TemplateContents < Node
    def append_html5lib_dump(lines, depth)
      children.each { |child| child.append_html5lib_dump(lines, depth) }
    end
  end

  # Result of the HTML fragment parsing algorithm (§13.4).
  class DocumentFragment < Node
    attr_accessor :parse_errors

    def initialize
      super
      @parse_errors = []
    end

    def html5lib_dump
      lines = []
      children.each { |child| child.append_html5lib_dump(lines, 0) }
      lines.join("\n")
    end
  end

  class Document < Node
    attr_accessor :quirks_mode, :parse_errors, :character_encoding, :encoding_confidence

    def initialize
      super
      # :no_quirks | :quirks | :limited_quirks
      @quirks_mode = :no_quirks
      @parse_errors = []
      @character_encoding = nil
      @encoding_confidence = nil
    end

    def html5lib_dump
      lines = []
      children.each { |child| child.append_html5lib_dump(lines, 0) }
      lines.join("\n")
    end
  end

  class DocumentType < Node
    attr_reader :name, :public_id, :system_id

    def initialize(name, public_id = nil, system_id = nil)
      super()
      @name = name
      @public_id = public_id
      @system_id = system_id
    end

    def append_html5lib_dump(lines, depth)
      indent = "  " * depth
      if (public_id && !public_id.empty?) || (system_id && !system_id.empty?)
        pub = public_id || ""
        sys = system_id || ""
        lines << "| #{indent}<!DOCTYPE #{name} \"#{pub}\" \"#{sys}\">"
      else
        lines << "| #{indent}<!DOCTYPE #{name}>"
      end
    end
  end

  class Element < Node
    attr_reader :name, :namespace, :attributes
    attr_accessor :token # StartTagToken used to create this element (AAA / reconstruct)
    # §4.10.10 option selectedness / §4.10.17 selectedcontent disabled flag.
    attr_accessor :selectedness, :disabled

    def initialize(name, attributes: {}, namespace: HTML_NAMESPACE)
      super()
      @name = name
      @namespace = namespace
      @attributes = attributes.transform_keys(&:to_s)
      @token = nil
      @selectedness = false
      @disabled = false
      @template_contents = TemplateContents.new if html? && name == "template"
    end

    def html?
      namespace == HTML_NAMESPACE
    end

    def template_contents
      @template_contents ||= TemplateContents.new if html? && name == "template"
    end

    def append_html5lib_dump(lines, depth)
      indent = "  " * depth
      prefix = case namespace
      when HTML_NAMESPACE then ""
      when "http://www.w3.org/2000/svg" then "svg "
      when "http://www.w3.org/1998/Math/MathML" then "math "
      else ""
      end
      lines << "| #{indent}<#{prefix}#{name}>"
      attributes.keys.sort.each do |attr_name|
        lines << "| #{indent}  #{attr_name}=\"#{attributes[attr_name]}\""
      end
      if html? && name == "template"
        # html5lib dump: template children live under a synthetic "content" node.
        content_indent = "  " * (depth + 1)
        lines << "| #{content_indent}content"
        template_contents.children.each { |child| child.append_html5lib_dump(lines, depth + 2) }
      else
        children.each { |child| child.append_html5lib_dump(lines, depth + 1) }
      end
    end
  end

  class TextNode < Node
    attr_accessor :data

    def initialize(data = +"")
      super()
      @data = data
    end

    def append_html5lib_dump(lines, depth)
      indent = "  " * depth
      lines << "| #{indent}\"#{data}\""
    end
  end

  class Comment < Node
    attr_reader :data

    def initialize(data)
      super()
      @data = data
    end

    def append_html5lib_dump(lines, depth)
      indent = "  " * depth
      # html5lib tree dump prints PI-shaped comments as <?target data?>.
      lines << if (pi = html5lib_processing_instruction_dump)
        "| #{indent}#{pi}"
      else
        "| #{indent}<!-- #{data} -->"
      end
    end

    private

    # Match the html5lib/WPT tree-construction dump heuristic for comments that
    # came from <?...?> (bogus comment data starts with "?").
    def html5lib_processing_instruction_dump
      return unless data.start_with?("?")

      rest = data[1..]
      rest = rest.chop if rest.end_with?("?")
      m = rest.match(/\A([A-Za-z_][A-Za-z0-9_-]*)([\s\S]*)\z/)
      return unless m

      target, payload = m[1], m[2]
      return if target.match?(/\Axml/i)
      return if !payload.empty? && !payload.start_with?("?", *"\t\n\f\r ".chars)

      if payload.empty?
        "<?#{target} ?>"
      elsif payload.start_with?(*"\t\n\f\r ".chars)
        "<?#{target}#{payload.sub(/\A[\t\n\f\r ]+/, " ")}?>"
      else
        "<?#{target} #{payload}?>"
      end
    end
  end
end
