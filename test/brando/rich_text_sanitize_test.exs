defmodule Brando.RichTextSanitizeTest do
  # Rich text is checked as browsers parse it. Each payload below hides an
  # image with an error handler from a parser that is not HTML5's: in a
  # comment, a CDATA section, or the content of an element whose content
  # browsers read differently (xmp, noscript, noembed, noframes), or in a
  # comment inside an svg. The handlers would only set document.title.
  use ExUnit.Case, async: true

  alias Brando.RichText
  alias Brando.Villain.Blocks.TextBlock.Data

  @handler "<img src=x alt=MARKER onerror=document.title=this.alt>"

  @hidden %{
    comment: "<p>Hi</p><!-->#{@handler}-->",
    xmp: ~s(<p>Hi</p><xmp><p title="</xmp>#{@handler}"></p></xmp>),
    cdata: "<p>Hi</p><![CDATA[>#{@handler}]]>",
    noscript: ~s(<p>Hi</p><noscript><p title="</noscript>#{@handler}"></p></noscript>),
    noembed: ~s(<p>Hi</p><noembed><p title="</noembed>#{@handler}"></p></noembed>),
    noframes: ~s(<p>Hi</p><noframes><p title="</noframes>#{@handler}"></p></noframes>),
    plaintext: "<p>Hi</p><plaintext>#{@handler}"
  }

  @svg ~s(<svg viewBox="0 0 10 10"><!-->#{@handler}--></svg>)

  # What a browser builds from `html`.
  defp handlers(html), do: html |> LazyHTML.from_fragment() |> LazyHTML.query("[onerror]") |> Enum.count()

  test "the control is unsafe" do
    refute RichText.safe_html?("<p>Hi</p>" <> @handler)
    assert RichText.sanitize_html("<p>Hi</p>" <> @handler) == :error
  end

  for {name, payload} <- @hidden do
    @payload payload

    test "#{name}: refused as it is, and sanitized to text no browser builds a handler from" do
      refute RichText.safe_html?(@payload)

      case RichText.sanitize_html(@payload) do
        :error -> :ok
        {:ok, clean} -> assert handlers(clean) == 0
      end

      changeset = Data.changeset(%Data{}, %{text: @payload})

      if changeset.valid?,
        do: assert(handlers(Ecto.Changeset.get_field(changeset, :text)) == 0),
        else: assert(changeset.errors[:text])
    end
  end

  test "a comment inside an svg hides nothing" do
    refute RichText.safe_svg?(@svg)
    assert RichText.safe_svg?(~s(<svg viewBox="0 0 10 10"><title>Dot</title><circle cx="5" cy="5" r="4"/></svg>))
    refute RichText.safe_svg?(~s(<svg><foreignObject><p>x</p></foreignObject></svg>))
    refute RichText.safe_svg?(~s(<svg><style>p{}</style></svg>))
    refute RichText.safe_svg?(~s(<svg></svg><p>after</p>))
    assert RichText.safe_svg?(~s(<?xml version="1.0"?>\n<!-- Exported --><svg viewBox="0 0 1 1"></svg>\n))
    refute RichText.safe_svg?(~s(<!-- x --><svg><!-- inside --></svg>))
  end

  test "elements SVG and HTML share a name are seen in HTML" do
    for html <- [
          ~s(<iframe srcdoc="x"></iframe>),
          ~s(<video src="x" onerror="x"></video>),
          ~s(<canvas onclick="x"></canvas>),
          ~s(<a href="javascript:x">a</a>),
          ~s(<span onclick="x">a</span>),
          ~s(<font onclick="x">a</font>),
          ~s(<audio onplay="x"></audio>)
        ] do
      refute RichText.safe_html?(html), html
      assert RichText.sanitize_html(html) == :error, html
    end
  end

  test "Markdown is checked as the HTML it renders" do
    refute "[Read more](javascript:document.title='MARKER')"
           |> Brando.Markdown.to_html!(breaks: true)
           |> RichText.safe_html?()
  end

  test "addresses are read after the parser decodes them" do
    for html <- [
          ~s(<a href="&#106;avascript:x">a</a>),
          ~s(<a href="java\tscript:x">a</a>),
          ~s(<a href=" javascript:x">a</a>),
          ~s(<a HREF="javascript:x">a</a>),
          ~s(<p ONCLICK="x">a</p>),
          ~s(<p a"onclick="x">a</p>),
          ~s(<a href="whatsapp://send?text=hi">a</a>)
        ] do
      refute RichText.safe_html?(html), html
      assert RichText.sanitize_html(html) == :error, html
    end
  end

  # What Brando's editor (TipTap's StarterKit, links, colour, text align,
  # sub/superscript, styles, footnotes and identifier links) writes, and
  # browsers serialize: kept as it is.
  @editor_html [
    ~s(<p>Plain text, æøå &amp; “quotes” — 'apostrophes' and "doubles" &lt;tag&gt;</p>),
    ~s(<p>Non&nbsp;breaking&nbsp;space and <br>hard break</p><p></p>),
    ~s(<h2>Heading</h2><h3 style="text-align: center">Centred</h3><p style="text-align: right">Right</p>),
    ~s(<p><strong>Bold</strong> <em>italic</em> <s>strike</s> <u>under</u> <code>a &lt; b &amp;&amp; c</code> <sub>2</sub> <sup>3</sup></p>),
    ~s(<ul><li><p>One</p></li><li><p>Two</p><ol start="3"><li><p>Nested</p></li></ol></li></ul>),
    ~s{<blockquote><p>Quoted</p></blockquote><pre><code class="language-elixir">IO.puts("&lt;hi&gt;")</code></pre><hr>},
    ~s(<p><a target="_blank" rel="noopener noreferrer nofollow" href="https://example.com/?a=1&amp;b=2#x">External</a> <a href="/rooms" data-identifier-id="12" class="action-button">Rooms</a> <a href="mailto:post@example.com">Mail</a> <a href="tel:+4712345678">Phone</a></p>),
    ~s{<p><span style="color: rgb(255, 0, 0)">Red</span> <span class="small-caps">Caps</span></p><p class="lede">A lede</p>},
    ~s(<p>Body<sup data-footnote-uid="note-1">•</sup></p>),
    ~s(<p class="lede"><span id="getting-here" data-type="jump-anchor"><a class="action-button extra" href="/rooms" data-identifier-id="12">Rooms</a></span></p>),
    ~s(<p>Emoji 🎉 and a tab\tin text</p>\n<p>New line between</p>)
  ]

  test "ordinary editor content is kept as it is" do
    for html <- @editor_html do
      assert RichText.sanitize_html(html) == {:ok, html}
      assert RichText.safe_html?(html), html
      assert Data.changeset(%Data{}, %{text: html}).changes.text == html
    end
  end

  test "harmless normalisation of other markup" do
    assert RichText.sanitize_html("<p>a<br/>b</p>") == {:ok, "<p>a<br>b</p>"}
    assert RichText.sanitize_html("<p class='x'>a</p>") == {:ok, ~s(<p class="x">a</p>)}
    assert RichText.sanitize_html("<p>unclosed") == {:ok, "<p>unclosed</p>"}

    assert RichText.sanitize_html("<table><tr><td>x</td></tr></table>") ==
             {:ok, "<table><tbody><tr><td>x</td></tr></tbody></table>"}

    assert RichText.sanitize_html("<p>a<x-custom>b</x-custom></p>") == {:ok, "<p>ab</p>"}
  end

  test "markup on an element the check would not see is refused" do
    for html <- [
          ~s(<svg onload="document.title='MARKER'"></svg>),
          ~s(<x-custom onclick="document.title='MARKER'">Click</x-custom>),
          ~s(<p>Hi</p><body onload="document.title='MARKER'">),
          ~s(<p>Hi</p><html onclick="x">),
          ~s(<image src=x onerror="x">)
        ] do
      refute RichText.safe_html?(html), html
    end

    refute RichText.safe_svg?(~s(<svg><x-custom onclick="x"></x-custom></svg>))

    # HTML a parser drops or moves out of sight: inside an svg's desc or
    # title, table parts outside a table, a name lowercased beyond ASCII.
    for code <- [
          ~s(<svg><desc><img src="x" onerror="x"></desc></svg>),
          ~s(<svg><title><video onerror="x"></video></title></svg>),
          ~s(<svg><section onclick="x"></section></svg>),
          ~s(<svg><mas\u212A onclick="x"></mas\u212A></svg>)
        ] do
      refute RichText.safe_svg?(code), code
    end

    for html <- [
          ~s(<p>a</p><tr onclick="x"><td>b</td></tr>),
          ~s(<p>a</p><tr onclick="x"></tr></br></p>),
          ~s(<p>a<mar\u212A onmouseover="x">b</mar\u212A></p>)
        ] do
      refute RichText.safe_html?(html), html
    end

    # Sanitized, such an element and what it holds on itself is gone.
    assert RichText.sanitize_html(~s(<p>a<x-custom onclick="x">b</x-custom></p>)) == {:ok, "<p>ab</p>"}
    assert RichText.sanitize_html(~s(<svg onload="x"></svg>)) == :error
  end

  test "comments and hidden elements are left out of sanitized text" do
    assert RichText.sanitize_html("<p>Hi</p><!-- note --><p>there</p>") == {:ok, "<p>Hi</p><p>there</p>"}
    assert RichText.sanitize_html("<p>Hi</p><xmp>raw</xmp>") == {:ok, "<p>Hi</p>"}
    refute RichText.safe_html?("<p>Hi</p><!-- note -->")
  end
end
