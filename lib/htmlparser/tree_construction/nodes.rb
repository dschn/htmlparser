# frozen_string_literal: true

module HTMLParser
  HTML_NAMESPACE = "http://www.w3.org/1999/xhtml"

  # DOM Living Standard — ParentNode (Document / DocumentFragment / Element).
  # Tree-order walks over light children only (not <template> contents).
  module ParentNode
    # https://dom.spec.whatwg.org/#dom-nonelementparentnode-getelementbyid
    def get_element_by_id(id)
      id = id.to_s
      return nil if id.empty?

      each_element_descendant.find { |el| el.id == id }
    end

    # https://dom.spec.whatwg.org/#dom-document-getelementsbytagname
    # HTML documents: ASCII case-insensitive local-name match. `"*"` → all elements.
    def get_elements_by_tag_name(qualified_name)
      name = qualified_name.to_s
      if name == "*"
        each_element_descendant.to_a
      else
        each_element_descendant.select { |el| el.name.casecmp?(name) }
      end
    end

    # https://dom.spec.whatwg.org/#dom-document-getelementsbyclassname
    def get_elements_by_class_name(class_names)
      tokens = class_names.to_s.split(/\s+/).reject(&:empty?)
      return [] if tokens.empty?

      each_element_descendant.select do |el|
        list = el.class_list
        tokens.all? { |t| list.include?(t) }
      end
    end

    # Depth-first tree order over descendant Element nodes.
    def each_element_descendant(&block)
      return enum_for(:each_element_descendant) unless block

      stack = children.reverse
      while (node = stack.pop)
        if node.is_a?(Element)
          yield node
          stack.concat(node.children.reverse)
        elsif node.is_a?(Node)
          stack.concat(node.children.reverse)
        end
      end
    end
  end

  # Minimal DOM nodes for §13.2.6 tree construction + html5lib dump serialization.
  class Node
    attr_accessor :parent
    attr_reader :children

    def initialize
      @parent = nil
      @children = []
    end

    # DOM aliases (same objects as tree-construction `parent` / `children`).
    alias_method :parent_node, :parent
    alias_method :child_nodes, :children

    def first_child
      children.first
    end

    def last_child
      children.last
    end

    def next_sibling
      return nil unless parent

      siblings = parent.children
      idx = siblings.index(self)
      return nil unless idx

      siblings[idx + 1]
    end

    def previous_sibling
      return nil unless parent

      siblings = parent.children
      idx = siblings.index(self)
      return nil unless idx&.positive?

      siblings[idx - 1]
    end

    # https://dom.spec.whatwg.org/#dom-node-textcontent
    def text_content
      case self
      when TextNode, Comment, DocumentType
        data.to_s
      else
        children.map(&:text_content).join
      end
    end

    def text_content=(value)
      case self
      when TextNode
        self.data = value.to_s.dup
      when Comment
        @data = value.to_s.dup
      when DocumentType
        nil
      else
        children.dup.each { |child| remove_child(child) }
        s = value.to_s
        append_child(TextNode.new(s.dup)) unless s.empty?
      end
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

    # §13.3 — serialize this node's children (inner HTML / fragment serialization).
    def inner_html
      Serialize.serialize_children(self)
    end
  end

  InsertionLocation = Struct.new(:parent, :before)

  # DocumentFragment used as a template element's template contents (§4.12.3 / §13.2.6).
  class TemplateContents < Node
    include ParentNode

    def append_html5lib_dump(lines, depth)
      children.each { |child| child.append_html5lib_dump(lines, depth) }
    end
  end

  # Result of the HTML fragment parsing algorithm (§13.4).
  class DocumentFragment < Node
    include ParentNode

    attr_accessor :parse_errors

    def initialize
      super
      @parse_errors = []
    end

    def to_html
      inner_html
    end

    def html5lib_dump
      lines = []
      children.each { |child| child.append_html5lib_dump(lines, 0) }
      lines.join("\n")
    end
  end

  class Document < Node
    include ParentNode

    attr_accessor :quirks_mode, :parse_errors, :character_encoding, :encoding_confidence

    def initialize
      super
      # :no_quirks | :quirks | :limited_quirks
      @quirks_mode = :no_quirks
      @parse_errors = []
      @character_encoding = nil
      @encoding_confidence = nil
    end

    # §13.3 — serialize the document's children (doctype + html element, …).
    def to_html
      inner_html
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

    # DocumentType#data is not a DOM thing; text_content uses #name.
    def data
      name
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
    include ParentNode

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

    # DOM Element.tagName — uppercase for HTML-namespace elements.
    def tag_name
      html? ? name.upcase : name
    end

    def [](attr_name)
      attributes[attr_name.to_s]
    end

    def []=(attr_name, value)
      attributes[attr_name.to_s] = value.to_s
    end

    def has_attribute?(attr_name)
      attributes.key?(attr_name.to_s)
    end

    def id
      attributes["id"] || ""
    end

    def id=(value)
      attributes["id"] = value.to_s
    end

    def class_name
      attributes["class"] || ""
    end

    def class_name=(value)
      attributes["class"] = value.to_s
    end

    # Whitespace-split class tokens (DOMTokenList subset — Array for now).
    def class_list
      class_name.split(/\s+/).reject(&:empty?)
    end

    # §13.3 — serialize this element including its start/end tags.
    def outer_html
      Serialize.serialize_node(self)
    end

    def to_html
      outer_html
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
