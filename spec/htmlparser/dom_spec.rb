# frozen_string_literal: true

require "spec_helper"

RSpec.describe "minimal DOM API" do
  def parse(html)
    HTMLParser.parse(html)
  end

  describe "traversal" do
    it "exposes parent_node / child_nodes aliases and siblings" do
      doc = parse("<div id=a></div><p id=b></p>")
      body = doc.get_elements_by_tag_name("body").first
      div, p = body.child_nodes.grep(HTMLParser::Element)

      expect(div.parent_node).to eq(body)
      expect(div.next_sibling).to eq(p)
      expect(p.previous_sibling).to eq(div)
      expect(body.first_child).to eq(div)
      expect(body.last_child).to eq(p)
    end
  end

  describe "Element attributes" do
    it "supports id, class_list, [], and tag_name" do
      el = parse(%(<span id="x" class="foo  bar">hi</span>)).get_element_by_id("x")

      expect(el.tag_name).to eq("SPAN")
      expect(el.name).to eq("span")
      expect(el["id"]).to eq("x")
      expect(el.id).to eq("x")
      expect(el.class_name).to eq("foo  bar")
      expect(el.class_list).to eq(%w[foo bar])
      expect(el.has_attribute?("class")).to be(true)

      el["data-y"] = "1"
      expect(el["data-y"]).to eq("1")
    end
  end

  describe "ParentNode queries" do
    it "finds elements by id, tag name, and class name in tree order" do
      doc = parse(<<~HTML)
        <div id="root" class="wrap">
          <p class="a b">One</p>
          <p id="two" class="a">Two</p>
          <span class="b">Three</span>
        </div>
      HTML

      expect(doc.get_element_by_id("two").name).to eq("p")
      expect(doc.get_element_by_id("missing")).to be_nil
      expect(doc.get_element_by_id("")).to be_nil

      paragraphs = doc.get_elements_by_tag_name("P")
      expect(paragraphs.map { |e| e.text_content.strip }).to eq(%w[One Two])

      expect(doc.get_elements_by_tag_name("*").map(&:name)).to include("html", "body", "div", "p", "span")

      expect(doc.get_elements_by_class_name("a").map(&:id)).to eq(["", "two"])
      expect(doc.get_elements_by_class_name("a b").map { |e| e.text_content.strip }).to eq(%w[One])
    end

    it "does not walk into template contents from the document" do
      doc = parse(%(<template><div id="inside"></div></template><div id="outside"></div>))

      expect(doc.get_element_by_id("outside")).not_to be_nil
      expect(doc.get_element_by_id("inside")).to be_nil

      template = doc.get_elements_by_tag_name("template").first
      expect(template.template_contents.get_element_by_id("inside").name).to eq("div")
    end

    it "scopes queries to an element subtree" do
      doc = parse(%(<div id="a"><span id="s"></span></div><span id="other"></span>))
      div = doc.get_element_by_id("a")

      expect(div.get_element_by_id("s").name).to eq("span")
      expect(div.get_element_by_id("other")).to be_nil
      expect(div.get_elements_by_tag_name("span").size).to eq(1)
    end
  end

  describe "text_content" do
    it "concatenates descendant text and can replace element children" do
      doc = parse("<p>Hello <b>world</b></p>")
      p = doc.get_elements_by_tag_name("p").first

      expect(p.text_content).to eq("Hello world")

      p.text_content = "replaced"
      expect(p.children.size).to eq(1)
      expect(p.children.first).to be_a(HTMLParser::TextNode)
      expect(p.text_content).to eq("replaced")
    end
  end
end
