# frozen_string_literal: true

require "spec_helper"

RSpec.describe HTMLParser::Selectors do
  def parse(html)
    HTMLParser.parse(html)
  end

  describe "simple selectors" do
    it "matches type, id, class, universal, and attributes" do
      doc = parse(<<~HTML)
        <div id="root" class="wrap" data-x="1">
          <span class="a">one</span>
          <p class="a b">two</p>
        </div>
      HTML

      expect(doc.query_selector("p").text_content.strip).to eq("two")
      expect(doc.query_selector("#root").name).to eq("div")
      expect(doc.query_selector(".b").name).to eq("p")
      expect(doc.query_selector("[data-x]").id).to eq("root")
      expect(doc.query_selector('[data-x="1"]').id).to eq("root")
      expect(doc.query_selector_all("*").map(&:name)).to include("html", "div", "span", "p")
      expect(doc.query_selector("SPAN.a").text_content.strip).to eq("one")
    end

    it "supports the common attribute operators" do
      doc = parse(%(<a href="/docs/intro" title="HTML parser" lang="en-US" class="x y"></a>))
      a = doc.query_selector("a")

      expect(a.matches?('[href^="/docs"]')).to be(true)
      expect(a.matches?('[href$="intro"]')).to be(true)
      expect(a.matches?('[title*="parse"]')).to be(true)
      expect(a.matches?('[class~="y"]')).to be(true)
      expect(a.matches?('[lang|="en"]')).to be(true)
      expect(a.matches?('[href^="/other"]')).to be(false)
    end
  end

  describe "combinators" do
    it "supports descendant, child, adjacent, and sibling combinators" do
      doc = parse(<<~HTML)
        <section id="s">
          <div><p id="deep">d</p></div>
          <p id="a">a</p>
          <span>x</span>
          <p id="b">b</p>
        </section>
      HTML

      expect(doc.query_selector("section p#deep").id).to eq("deep")
      expect(doc.query_selector("section > p").id).to eq("a")
      expect(doc.query_selector_all("section > p").map(&:id)).to eq(%w[a b])
      expect(doc.query_selector("p + span").text_content).to eq("x")
      expect(doc.query_selector("p#a ~ p").id).to eq("b")
      expect(doc.query_selector("div > p#a")).to be_nil
    end
  end

  describe "pseudo-classes" do
    it "supports :not and :is" do
      doc = parse(%(<div><p class="a">1</p><p class="b">2</p><span class="a">3</span></div>))

      expect(doc.query_selector_all("p:not(.b)").map { |e| e.text_content }).to eq(%w[1])
      expect(doc.query_selector_all(":is(span, p.b)").map(&:name)).to eq(%w[p span])
    end

    it "supports :has with relative combinators" do
      doc = parse(<<~HTML)
        <section>
          <div class="card"><h2>Title</h2><p>Body</p></div>
          <div class="card"><p>Only body</p></div>
          <div class="wrap"><span class="x"></span><em class="y"></em></div>
        </section>
      HTML

      expect(doc.query_selector_all("div:has(h2)").map { |e| e.class_name }).to eq(["card"])
      expect(doc.query_selector("div:has(> h2)").class_name).to eq("card")
      expect(doc.query_selector("span:has(+ em)").class_name).to eq("x")
      expect(doc.query_selector("div:has(> p):not(:has(h2))").text_content.strip).to eq("Only body")
    end

    it "supports :nth-child, :nth-of-type, nth-last-*, and structural pseudos" do
      doc = parse(<<~HTML)
        <ul>
          <li>a</li>
          <li>b</li>
          <li>c</li>
        </ul>
        <div><span>s1</span><p>p</p><span>s2</span></div>
        <section><em></em></section>
      HTML

      expect(doc.query_selector_all("li:nth-child(odd)").map(&:text_content)).to eq(%w[a c])
      expect(doc.query_selector("li:nth-child(2)").text_content).to eq("b")
      expect(doc.query_selector("li:nth-last-child(1)").text_content).to eq("c")
      expect(doc.query_selector("li:first-child").text_content).to eq("a")
      expect(doc.query_selector("li:last-child").text_content).to eq("c")
      expect(doc.query_selector_all("span:nth-of-type(2)").map(&:text_content)).to eq(%w[s2])
      expect(doc.query_selector("span:nth-last-of-type(1)").text_content).to eq("s2")
      expect(doc.query_selector("em:only-child").name).to eq("em")
      expect(doc.query_selector("em:empty").name).to eq("em")
      expect(doc.query_selector(":root").name).to eq("html")
    end

    it "supports :checked, :disabled, :enabled, and attribute i flag" do
      doc = parse(<<~HTML)
        <form>
          <input type="checkbox" checked>
          <input type="text" disabled>
          <input type="text" name="ok">
          <option selected>A</option>
        </form>
        <p data-x="AbC"></p>
      HTML

      expect(doc.query_selector("input:checked")["type"]).to eq("checkbox")
      expect(doc.query_selector("option:checked").text_content).to eq("A")
      expect(doc.query_selector("input:disabled")["type"]).to eq("text")
      expect(doc.query_selector_all("input:enabled").map { |e| e["type"] }).to eq(%w[checkbox text])
      expect(doc.query_selector('p[data-x="abc" i]').name).to eq("p")
      expect(doc.query_selector('p[data-x="abc"]')).to be_nil
    end
  end

  describe "selector lists and Element#matches?" do
    it "ORs comma-separated selectors and tests matches? on an element" do
      doc = parse(%(<div><a id="l">link</a><button class="go">Go</button></div>))
      btn = doc.query_selector("button")

      expect(doc.query_selector("a, button").name).to eq("a")
      expect(doc.query_selector_all("a, .go").map(&:name)).to eq(%w[a button])
      expect(btn.matches?("button.go")).to be(true)
      expect(btn.matches?("a")).to be(false)
    end
  end

  describe "scoping" do
    it "searches only descendants of the query root" do
      doc = parse(%(<div id="a"><span id="in"></span></div><span id="out"></span>))
      div = doc.query_selector("#a")

      expect(div.query_selector("span").id).to eq("in")
      expect(div.query_selector("#out")).to be_nil
    end

    it "does not pierce template contents from the document" do
      doc = parse(%(<template><p class="t">hi</p></template><p class="t">out</p>))
      expect(doc.query_selector("p.t").text_content).to eq("out")
      template = doc.query_selector("template")
      expect(template.template_contents.query_selector("p.t").text_content).to eq("hi")
    end
  end

  describe "errors" do
    it "raises SelectorError for empty or unsupported selectors" do
      doc = parse("<div></div>")
      expect { doc.query_selector("") }.to raise_error(HTMLParser::SelectorError)
      expect { doc.query_selector("div:hover") }.to raise_error(HTMLParser::SelectorError)
    end
  end
end
