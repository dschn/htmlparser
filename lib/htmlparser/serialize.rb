# frozen_string_literal: true

module HTMLParser
  # §13.3 Serializing HTML fragments
  # https://html.spec.whatwg.org/multipage/parsing.html#serializing-html-fragments
  #
  # Serializes the *children* of a Document / Element / DocumentFragment.
  module Serialize
    VOID_ELEMENTS = %w[
      area base basefont bgsound br col embed frame hr img input keygen
      link meta param source track wbr
    ].freeze

    RAW_TEXT_PARENTS = %w[
      style script xmp iframe noembed noframes plaintext
    ].freeze

    SVG_NAMESPACE = "http://www.w3.org/2000/svg"
    MATHML_NAMESPACE = "http://www.w3.org/1998/Math/MathML"
    XML_NAMESPACE = "http://www.w3.org/XML/1998/namespace"
    XMLNS_NAMESPACE = "http://www.w3.org/2000/xmlns/"
    XLINK_NAMESPACE = "http://www.w3.org/1999/xlink"

    module_function

    # HTML fragment serialization algorithm for `node`'s children.
    def serialize_children(node)
      s = +""
      children_for(node).each do |child|
        s << serialize_node(child)
      end
      s
    end

    def serialize_node(current)
      case current
      when Element
        serialize_element(current)
      when TextNode
        serialize_text(current)
      when Comment
        "<!--#{current.data}-->"
      when DocumentType
        serialize_doctype(current)
      else
        +""
      end
    end

    def children_for(node)
      if node.is_a?(Element) && node.html? && node.name == "template"
        node.template_contents.children
      else
        node.children
      end
    end

    def serialize_as_void?(element)
      element.html? && VOID_ELEMENTS.include?(element.name)
    end

    def serialize_element(element)
      tagname = element_tag_name(element)
      s = +"<#{tagname}"
      element.attributes.each do |name, value|
        s << " #{serialize_attribute_name(name)}=\"#{escape_string(value, attribute_mode: true)}\""
      end
      s << ">"
      return s if serialize_as_void?(element)

      s << serialize_children(element)
      s << "</#{tagname}>"
      s
    end

    def element_tag_name(element)
      case element.namespace
      when HTML_NAMESPACE, MATHML_NAMESPACE, SVG_NAMESPACE
        element.name
      else
        element.name
      end
    end

    # Our tree stores foreign attrs in html5lib dump form ("xlink href"); reverse to
    # the serialized name ("xlink:href").
    def serialize_attribute_name(name)
      name = name.to_s
      if name.include?(" ")
        prefix, local = name.split(" ", 2)
        "#{prefix}:#{local}"
      else
        name
      end
    end

    def serialize_text(text)
      parent = text.parent
      data = text.data.to_s

      if parent.is_a?(Element) && parent.html? && RAW_TEXT_PARENTS.include?(parent.name)
        return data
      end

      s = +""
      # §13.3 — historical: a leading LF in pre/textarea/listing is dropped on parse
      # (`ignore_next_lf`); emit an extra LF so round-trips keep the DOM text.
      if parent.is_a?(Element) && parent.html? &&
          %w[pre textarea listing].include?(parent.name) && data.start_with?("\n")
        s << "\n"
      end
      s << escape_string(data, attribute_mode: false)
      s
    end

    def serialize_doctype(doctype)
      name = doctype.name.to_s
      pub = doctype.public_id
      sys = doctype.system_id
      pub_present = !pub.nil? && !pub.empty?
      sys_present = !sys.nil? && !sys.empty?

      if pub_present
        %(<!DOCTYPE #{name} PUBLIC "#{pub}" "#{sys || ""}">)
      elsif sys_present
        %(<!DOCTYPE #{name} SYSTEM "#{sys}">)
      else
        "<!DOCTYPE #{name}>"
      end
    end

    # Escaping a string (as described for text / attribute mode).
    def escape_string(string, attribute_mode:)
      out = +""
      string.to_s.each_char do |c|
        out << case c
        when "&" then "&amp;"
        when "\u00A0" then "&nbsp;"
        when '"' then attribute_mode ? "&quot;" : c
        when "<" then attribute_mode ? c : "&lt;"
        when ">" then attribute_mode ? c : "&gt;"
        when "\r" then "&#13;" # keep CR through round-trip (input preprocess maps raw CR→LF)
        else c
        end
      end
      out
    end
  end
end
