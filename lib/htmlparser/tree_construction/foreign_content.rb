# frozen_string_literal: true

module HTMLParser
  class TreeConstruction
    # §13.2.6.5 The rules for parsing tokens in foreign content
    module ForeignContent
      MATHML_TEXT_INTEGRATION = %w[mi mo mn ms mtext].freeze
      SVG_HTML_INTEGRATION = %w[foreignObject desc title].freeze

      HTML_BREAKOUT_START_TAGS = %w[
        b big blockquote body br center code dd div dl dt em embed
        h1 h2 h3 h4 h5 h6 head hr i img li listing menu meta nobr
        ol p pre ruby s small span strong strike sub sup table tt u ul var
      ].freeze

      SVG_TAG_NAME_MAP = {
        "altglyph" => "altGlyph",
        "altglyphdef" => "altGlyphDef",
        "altglyphitem" => "altGlyphItem",
        "animatecolor" => "animateColor",
        "animatemotion" => "animateMotion",
        "animatetransform" => "animateTransform",
        "clippath" => "clipPath",
        "feblend" => "feBlend",
        "fecolormatrix" => "feColorMatrix",
        "fecomponenttransfer" => "feComponentTransfer",
        "fecomposite" => "feComposite",
        "feconvolvematrix" => "feConvolveMatrix",
        "fediffuselighting" => "feDiffuseLighting",
        "fedisplacementmap" => "feDisplacementMap",
        "fedistantlight" => "feDistantLight",
        "fedropshadow" => "feDropShadow",
        "feflood" => "feFlood",
        "fefunca" => "feFuncA",
        "fefuncb" => "feFuncB",
        "fefuncg" => "feFuncG",
        "fefuncr" => "feFuncR",
        "fegaussianblur" => "feGaussianBlur",
        "feimage" => "feImage",
        "femerge" => "feMerge",
        "femergenode" => "feMergeNode",
        "femorphology" => "feMorphology",
        "feoffset" => "feOffset",
        "fepointlight" => "fePointLight",
        "fespecularlighting" => "feSpecularLighting",
        "fespotlight" => "feSpotLight",
        "fetile" => "feTile",
        "feturbulence" => "feTurbulence",
        "foreignobject" => "foreignObject",
        "glyphref" => "glyphRef",
        "lineargradient" => "linearGradient",
        "radialgradient" => "radialGradient",
        "textpath" => "textPath"
      }.freeze

      SVG_ATTR_MAP = {
        "attributename" => "attributeName",
        "attributetype" => "attributeType",
        "basefrequency" => "baseFrequency",
        "baseprofile" => "baseProfile",
        "calcmode" => "calcMode",
        "clippathunits" => "clipPathUnits",
        "diffuseconstant" => "diffuseConstant",
        "edgemode" => "edgeMode",
        "filterunits" => "filterUnits",
        "glyphref" => "glyphRef",
        "gradienttransform" => "gradientTransform",
        "gradientunits" => "gradientUnits",
        "kernelmatrix" => "kernelMatrix",
        "kernelunitlength" => "kernelUnitLength",
        "keypoints" => "keyPoints",
        "keysplines" => "keySplines",
        "keytimes" => "keyTimes",
        "lengthadjust" => "lengthAdjust",
        "limitingconeangle" => "limitingConeAngle",
        "markerheight" => "markerHeight",
        "markerunits" => "markerUnits",
        "markerwidth" => "markerWidth",
        "maskcontentunits" => "maskContentUnits",
        "maskunits" => "maskUnits",
        "numoctaves" => "numOctaves",
        "pathlength" => "pathLength",
        "patterncontentunits" => "patternContentUnits",
        "patterntransform" => "patternTransform",
        "patternunits" => "patternUnits",
        "pointsatx" => "pointsAtX",
        "pointsaty" => "pointsAtY",
        "pointsatz" => "pointsAtZ",
        "preservealpha" => "preserveAlpha",
        "preserveaspectratio" => "preserveAspectRatio",
        "primitiveunits" => "primitiveUnits",
        "refx" => "refX",
        "refy" => "refY",
        "repeatcount" => "repeatCount",
        "repeatdur" => "repeatDur",
        "requiredextensions" => "requiredExtensions",
        "requiredfeatures" => "requiredFeatures",
        "specularconstant" => "specularConstant",
        "specularexponent" => "specularExponent",
        "spreadmethod" => "spreadMethod",
        "startoffset" => "startOffset",
        "stddeviation" => "stdDeviation",
        "stitchtiles" => "stitchTiles",
        "surfacescale" => "surfaceScale",
        "systemlanguage" => "systemLanguage",
        "tablevalues" => "tableValues",
        "targetx" => "targetX",
        "targety" => "targetY",
        "textlength" => "textLength",
        "viewbox" => "viewBox",
        "viewtarget" => "viewTarget",
        "xchannelselector" => "xChannelSelector",
        "ychannelselector" => "yChannelSelector",
        "zoomandpan" => "zoomAndPan"
      }.freeze

      # Token attribute name → html5lib dump key (prefix + " " + localName).
      FOREIGN_ATTR_MAP = {
        "xlink:actuate" => "xlink actuate",
        "xlink:arcrole" => "xlink arcrole",
        "xlink:href" => "xlink href",
        "xlink:role" => "xlink role",
        "xlink:show" => "xlink show",
        "xlink:title" => "xlink title",
        "xlink:type" => "xlink type",
        "xml:lang" => "xml lang",
        "xml:space" => "xml space",
        "xmlns" => "xmlns",
        "xmlns:xlink" => "xmlns xlink"
      }.freeze

      private

      # §13.2.4.2 — adjusted current node (fragment case).
      def adjusted_current_node
        if fragment? && stack_of_open_elements.to_a.size == 1
          @context_element
        else
          current_node
        end
      end

      def foreign_content?(token)
        return false if token.is_a?(EOFToken)
        return false if stack_of_open_elements.empty?

        node = adjusted_current_node
        return false if node.nil? || node.html?

        if mathml_text_integration_point?(node)
          case token
          when CharacterToken
            return false
          when StartTagToken
            return false unless %w[mglyph malignmark].include?(token.name)
          end
        end

        if svg_html_integration_point?(node)
          return false if token.is_a?(CharacterToken) || token.is_a?(StartTagToken)
        end

        if node.namespace == MATHML_NAMESPACE && node.name == "annotation-xml"
          case token
          when StartTagToken
            return false if token.name == "svg"
            return false if mathml_annotation_xml_integration_point?(node)
          when CharacterToken
            return false if mathml_annotation_xml_integration_point?(node)
          end
        end

        true
      end

      def mathml_text_integration_point?(node)
        node.namespace == MATHML_NAMESPACE && MATHML_TEXT_INTEGRATION.include?(node.name)
      end

      def svg_html_integration_point?(node)
        node.namespace == SVG_NAMESPACE && SVG_HTML_INTEGRATION.include?(node.name)
      end

      def mathml_annotation_xml_integration_point?(node)
        encoding = node.attributes["encoding"]
        return false unless encoding

        case encoding.downcase
        when "application/xhtml+xml", "text/html" then true
        else false
        end
      end

      # §13.2.6.5
      def process_foreign_content(token)
        case token
        when CharacterToken
          process_foreign_character(token)
        when CommentToken
          insert_comment(token)
        when DocTypeToken
          parse_error("unexpected-doctype")
        when StartTagToken
          process_foreign_start_tag(token)
        when EndTagToken
          # End tags br/p share the HTML breakout path with the breakout start tags.
          if %w[br p].include?(token.name)
            unexpected_start_tag_in_foreign_content(token)
          else
            process_foreign_end_tag(token)
          end
        end
      end

      # §13.2.6.5 — Any character token.
      def process_foreign_character(token)
        # Spec splits NULL / whitespace / any-other; null must not clear frameset-ok.
        token.value.each_char do |char|
          if char == "\u0000"
            parse_error("invalid-codepoint-in-foreign-content")
            insert_character("\uFFFD")
          elsif whitespace_string?(char)
            insert_character(char)
          else
            insert_character(char)
            @frameset_ok = false
          end
        end
      end

      # §13.2.6.5 — Any start tag token.
      def process_foreign_start_tag(token)
        if HTML_BREAKOUT_START_TAGS.include?(token.name) ||
            (token.name == "font" && font_breakout?(token))
          unexpected_start_tag_in_foreign_content(token)
          return
        end

        foreign_start_tag(token)
      end

      def font_breakout?(token)
        token.attributes.any? { |a| %w[color face size].include?(a[:name]) }
      end

      # §13.2.6.5 — Any other start tag (MathML / SVG adjust + insert).
      def foreign_start_tag(token)
        ns = adjusted_current_node.namespace
        case ns
        when MATHML_NAMESPACE
          adjust_mathml_attributes(token)
        when SVG_NAMESPACE
          adjust_svg_tag_name(token)
          adjust_svg_attributes(token)
        end
        adjust_foreign_attributes(token)
        insert_foreign_element(token, ns)
      end

      # §13.2.6.5 — HTML integration / breakout start tags (and end tags br/p).
      def unexpected_start_tag_in_foreign_content(token)
        parse_error("unexpected-start-tag")
        loop do
          node = current_node
          break if node.nil?
          break if node.html? || mathml_text_integration_point?(node) || svg_html_integration_point?(node)

          stack_of_open_elements.pop
        end
        # Process in the current HTML insertion mode without re-checking foreign content
        # (fragment case: adjusted current node may still be the foreign context element).
        process_in_current_html_insertion_mode(token)
      end

      # §13.2.6.5 — Any other end tag token.
      def process_foreign_end_tag(token)
        first = true
        nodes = stack_of_open_elements.to_a
        idx = nodes.size - 1
        loop do
          return if idx < 0

          node = nodes[idx]
          if !first && node.html?
            process_in_current_html_insertion_mode(token)
            return
          end

          if node.name.casecmp?(token.name)
            # Pop until this node (inclusive).
            loop do
              el = stack_of_open_elements.pop
              break if el.nil? || el.equal?(node)
            end
            return
          end

          parse_error("unexpected-end-tag") if first
          first = false
          idx -= 1
        end
      end

      # §13.2.6.5 — re-enter the current HTML insertion mode after a foreign breakout.
      def process_in_current_html_insertion_mode(token)
        # Stay in HTML rules for this token (and any HTML-mode reprocesses it triggers).
        guard = 0
        loop do
          @reprocess = false
          method = :"process_#{@insertion_mode}"
          if respond_to?(method, true)
            send(method, token)
          else
            @insertion_mode = :in_body
            process_in_body(token)
          end
          guard += 1
          raise "html reprocess loop after foreign breakout" if guard > 64
          break unless @reprocess
        end
      end

      # §13.2.6.5 — adjust + insert for an in-body MathML/SVG start tag entry.
      def enter_foreign(token, namespace)
        case namespace
        when MATHML_NAMESPACE
          adjust_mathml_attributes(token)
        when SVG_NAMESPACE
          adjust_svg_tag_name(token)
          adjust_svg_attributes(token)
        end
        adjust_foreign_attributes(token)
        insert_foreign_element(token, namespace)
      end

      # §13.2.6.1 — create an element for a token (foreign namespace) and insert it.
      def insert_foreign_element(token, namespace)
        attrs = {}
        token.attributes.each do |attr|
          attrs[attr[:name]] ||= attr[:value]
        end
        element = Element.new(token.name, attributes: attrs, namespace: namespace)
        element.token = token
        insert_node_at(appropriate_place_for_inserting_a_node, element)
        if token.self_closing
          acknowledge_self_closing_flag(token)
        else
          stack_of_open_elements.push(element)
        end
        element
      end

      def adjust_svg_tag_name(token)
        mapped = SVG_TAG_NAME_MAP[token.name]
        token.name = mapped if mapped
      end

      def adjust_svg_attributes(token)
        token.attributes.each do |attr|
          mapped = SVG_ATTR_MAP[attr[:name]]
          attr[:name] = mapped if mapped
        end
      end

      def adjust_mathml_attributes(token)
        token.attributes.each do |attr|
          attr[:name] = "definitionURL" if attr[:name] == "definitionurl"
        end
      end

      def adjust_foreign_attributes(token)
        token.attributes.each do |attr|
          mapped = FOREIGN_ATTR_MAP[attr[:name]]
          attr[:name] = mapped if mapped
        end
      end
    end
  end
end
