defmodule Brando.HTMLParsingTest do
  @moduledoc """
  What each runtime HTML rewrite and text extraction gives for markup that
  parsers disagree on: whitespace between inline elements, entities, void and
  boolean attributes, SVG attribute case, misnested and unclosed tags.

  These were written against Floki's parser. Where lexbor (`LazyHTML`) gives
  something else, a comment says what Floki gave.
  """
  use Brando.ConnCase, async: true

  alias Brando.Content.BlockSlots
  alias Brando.Content.BlockSlots.Lifecycle
  alias Brando.Content.Transfer.Portable
  alias Brando.Villain.Footnotes
  alias Brando.Villain.Markdown.HTML, as: MarkdownHTML

  defp marker(uid), do: ~s(<sup data-footnote-uid="#{uid}">•</sup>)
  defp definition(uid, html), do: ~s(<template data-brando-footnote="#{uid}">#{html}</template>)

  defp noteref(scope, n \\ 1),
    do:
      ~s(<sup data-footnote-uid="a" class="footnote-reference"><a href="#fn-#{scope}-YQ" id="fnref-#{scope}-#{n}" role="doc-noteref" aria-label="Footnote #{n}">#{n}</a></sup>)

  @article "YXJ0aWNsZQ"

  describe "footnotes" do
    test "keeps the text, entities, void elements and attributes around a reference" do
      html =
        ~s(<p><strong>Bold</strong> <em>it's</em> &amp; "q"#{marker("a")}<br>next</p>\n) <>
          ~s(<p><img src="/a.jpg" alt="A &quot;B&quot;"><input disabled></p>) <>
          definition("a", ~s(<p>Source &amp; <a href="/x?a=1&b=2">link</a> <em>one</em> <em>two</em></p>))

      result = Footnotes.render(html)

      # Floki dropped whitespace-only text: `<strong>Bold</strong><em>`, `</p><p>`,
      # `<em>one</em><em>two</em>`; and wrote `disabled="disabled"`.
      assert result.html ==
               ~s(<p><strong>Bold</strong> <em>it&#39;s</em> &amp; &quot;q&quot;#{noteref(@article)}<br/>next</p>\n) <>
                 ~s(<p><img src="/a.jpg" alt="A &quot;B&quot;"/><input disabled=""/></p>)

      assert hd(result.notes).html ==
               ~s(<p>Source &amp; <a href="/x?a=1&amp;b=2">link</a> <em>one</em> <em>two</em></p>)
    end

    test "SVG beside a reference" do
      result = Footnotes.render(~s(<svg viewBox="0 0 10 10"><path d="M0"/></svg>#{marker("a")}) <> definition("a", "x"))
      # Floki lowercased it to `viewbox`, which SVG ignores.
      assert result.html == ~s(<svg viewBox="0 0 10 10"><path d="M0"></path></svg>#{noteref(@article)})
    end

    test "a block element inside a paragraph" do
      result = Footnotes.render(~s(<p>A#{marker("a")}<div>block</div></p>) <> definition("a", "x"))
      # As a browser reads it. Floki kept the div inside the paragraph.
      assert result.html == ~s(<p>A#{noteref(@article)}</p><div>block</div><p></p>)
    end

    test "a rendered result renumbers with its note body intact" do
      first = Footnotes.render(marker("a") <> definition("a", "<p>Note <b>x</b> <i>y</i></p>")) |> Footnotes.to_html()
      result = first |> Footnotes.render(scope: "c") |> Footnotes.to_html()

      assert result ==
               noteref("Yw") <>
                 ~s(<section class="footnotes" role="doc-endnotes" data-brando-footnotes><h2>Notes &amp; sources</h2>) <>
                 ~s(<ol><li id="fn-Yw-YQ" data-brando-note="a" value="1"><div data-footnote-body>) <>
                 ~s(<p>Note <b>x</b> <i>y</i></p></div><nav aria-label="Back to text">) <>
                 ~s(<a class="footnote-backlink" role="doc-backlink" href="#fnref-Yw-1" aria-label="Return to reference 1">↩</a>) <>
                 ~s(</nav></li></ol></section>)
    end
  end

  describe "HTML to Markdown" do
    test "inline elements separated by a space" do
      # Floki: "**Bold***text*"
      assert MarkdownHTML.to_markdown("<p><strong>Bold</strong> <em>text</em></p>") == "**Bold** *text*"
    end

    test "a table with head and body" do
      html =
        "<table><thead><tr><th>A</th><th>B</th></tr></thead><tbody><tr><td>1</td><td>2</td></tr></tbody></table>"

      assert MarkdownHTML.to_markdown(html) == "| A | B |\n| --- | --- |\n| 1 | 2 |"
    end

    test "table rows without a table, as a row module renders them" do
      assert MarkdownHTML.to_markdown("<tr><td>Suite</td><td>40</td></tr><tr><td>Room</td><td>20</td></tr>") ==
               "| Suite | 40 |\n| --- | --- |\n\n| Room | 20 |\n| --- | --- |"
    end

    test "a picture gives its img, a video its source" do
      assert MarkdownHTML.to_markdown(~s(<picture><source srcset="/a.webp"><img src="/a.jpg" alt="A"></picture>)) ==
               "![A](http://localhost/a.jpg)"

      assert MarkdownHTML.to_markdown(~s(<video><source src="/v.mp4"></video>)) == "<http://localhost/v.mp4>"
    end

    test "a pre that starts with a line break" do
      # The parser drops the line break, as browsers do. Floki kept it, which
      # gave a fenced block with an empty first line: "```\n\nline1\n  line2\n```"
      assert MarkdownHTML.to_markdown("<pre>\nline1\n  line2\n</pre>") == "    line1\n      line2"
    end

    test "a block element inside a paragraph" do
      # Floki: "IntroBlocktail"
      assert MarkdownHTML.to_markdown("<p>Intro<div>Block</div>tail</p>") == "Intro\n\nBlock\n\ntail"
    end

    test "unclosed paragraphs and formatting" do
      # Floki nested the second paragraph in the first: "OneTwo **bold**"
      assert MarkdownHTML.to_markdown("<p>One<p>Two <b>bold") == "One\n\nTwo **bold**"
    end

    test "indented list items and paragraphs" do
      html = "<ul>\n  <li>One</li>\n  <li><p>Two</p>\n<p>Three</p></li>\n</ul>"
      assert MarkdownHTML.to_markdown(html) == "- One\n- Two\n  Three"
    end

    test "passed-through Markdown, scripts left out" do
      assert MarkdownHTML.to_markdown("<brando-markdown>## Title &amp; more</brando-markdown>") == "## Title & more"
      assert MarkdownHTML.to_markdown("<p>a</p><script>alert(1)</script><p>b</p>") == "a\n\nb"
    end
  end

  describe "rewriting identifier links" do
    @html ~s(<p><strong>Hi</strong> <a data-identifier-id="7" href="/old">it's</a> &amp; "q"<br>x</p>\n<p>y</p>)

    # Floki dropped whitespace-only text: `<strong>Hi</strong><a`, `</p><p>`.
    @relinked ~s(<p><strong>Hi</strong> <a data-identifier-id="7" href="/new?a=1&amp;b=2">it&#39;s</a> &amp; &quot;q&quot;<br/>x</p>\n<p>y</p>)

    test "rich text relinks the anchor and keeps the rest" do
      assert Brando.RichText.update_identifier_url(@html, 7, "/new?a=1&b=2") == {:updated, @relinked}

      assert Brando.RichText.contains_identifier?(@html, 7)
      refute Brando.RichText.contains_identifier?(@html, 8)
    end

    test "an import resolves the identifier token" do
      html = String.replace(@html, ~s("7"), ~s("tok1"))
      bindings = %{"tok1" => %{id: 7, url: "/new?a=1&b=2", external_url: nil}}

      assert Portable.decode_values(html, bindings) == @relinked
    end
  end

  describe "footnote markers in block slots" do
    test "remapping a marker keeps the rest" do
      html = ~s(<p><strong>A</strong> <em>b</em><sup data-footnote-uid="old">•</sup> it's &amp;</p>\n<p>c</p>)

      # Floki: `<strong>A</strong><em>b</em>` and `</p><p>`
      assert BlockSlots.remap_markers(html, %{"old" => "new"}) ==
               ~s(<p><strong>A</strong> <em>b</em><sup data-footnote-uid="new">•</sup> it&#39;s &amp;</p>\n<p>c</p>)
    end

    test "marker uids come from sup and span markers only" do
      html = ~s(<p><sup data-footnote-uid="a">1</sup><span data-footnote-uid="b"></span><b data-footnote-uid="c"></b></p>)
      assert Lifecycle.marker_uids(html) == MapSet.new(["a", "b"])
    end
  end

  describe "plain text" do
    test "search text" do
      html =
        ~s(<p><strong>Bold</strong> <em>text</em></p>\n<p>Two<br>lines &amp; more</p>) <>
          ~s(<style>.x{}</style><script>go</script><ul><li>a</li><li>b</li></ul>)

      # Floki: "Boldtext Two lines & more a b"
      assert Brando.Search.Text.plain(html) == "Bold text Two lines & more a b"
    end

    test "caption text" do
      # Floki: "Boldtext x y"
      assert Brando.Captions.text(~s(<p><strong>Bold</strong> <em>text</em></p><p>x&nbsp;y</p>)) == "Bold text x y"
      refute Brando.Captions.present?("<p><br></p>")
      assert Brando.Captions.present?("<untitled>")
    end

    test "a transfer preview's text lines" do
      ref = %{
        "name" => "text",
        "data" => %{"data" => %{"text" => "<p><strong>A</strong> <em>b</em></p>\n<p>Two<br>lines</p>"}}
      }

      lines = BrandoAdmin.ContentPreview.lines([%{"description" => "Text", "refs" => [ref]}])
      # Floki: "Ab"
      assert Enum.map(lines, & &1.text) == ["Text", "A b", "Two", "lines"]
    end

    test "an entry's Markdown title" do
      assert Brando.SEO.Markdown.title(%Brando.Pages.Page{title: "Rock &amp; <em>Roll</em>"}) == "Rock & Roll"
    end
  end

  describe "other parses" do
    test "a module sketch keeps SVG attributes in SVG's case" do
      svg =
        ~s(<svg viewBox="0 0 60 40"><rect x="1" y="2" width="3" height="4" stroke-width="2" fill="#000"/>) <>
          ~s(<g><circle cx="1" cy="2" r="3"/></g></svg>)

      assert Brando.Content.ModuleSketch.sanitize(svg) ==
               {:ok,
                ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 60 40">) <>
                  ~s(<rect x="1" y="2" width="3" height="4" stroke-width="2" fill="#000"/>) <>
                  ~s(<g><circle cx="1" cy="2" r="3"/></g></svg>)}
    end

    test "external Markdown renders to safe HTML with heading ids" do
      document = %{
        markdown:
          "# Hello *world*\n\nText with **bold** and [link](./a.md) and `code`.\n\n" <>
            "| a | b |\n|---|---|\n| 1 | 2 |\n\n```elixir\nIO.puts(1)\n```\n",
        path: "docs/x.md",
        repository: "o/r",
        commit: "abc"
      }

      # MDEx's line breaks between tags stay; Floki dropped them.
      assert Brando.MarkdownSources.Renderer.render(document) ==
               {:ok,
                ~s(<h1 id="hello-world">Hello <em>world</em></h1>\n) <>
                  ~s(<p>Text with <strong>bold</strong> and <a href="https://github.com/o/r/blob/abc/docs/a.md">link</a> and <code>code</code>.</p>\n) <>
                  ~s(<table>\n<thead>\n<tr>\n<th>a</th>\n<th>b</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>1</td>\n<td>2</td>\n</tr>\n</tbody>\n</table>\n) <>
                  ~s(<pre><code class="language-elixir">IO.puts\(1\)\n</code></pre>)}
    end

    test "a preview srcset is read with its character references decoded" do
      assert Brando.SSG.PreviewRewrite.html(~s(<img srcset="/a.jpg 1x,&#32;/b.jpg 2x">), "/p", ["https://x.no"]) ==
               ~s(<img srcset="/p/a.jpg 1x, /p/b.jpg 2x">)
    end
  end
end
