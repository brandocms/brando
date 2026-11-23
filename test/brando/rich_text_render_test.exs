defmodule Brando.RichTextRenderTest do
  # Stored rich text renders with what saving it now would refuse removed: a
  # refused element with what it holds, a refused attribute or address. The
  # rest of its markup is kept (#3859).
  use Brando.ConnCase, async: true

  alias Brando.RichText
  alias Brando.RichTextRows.Entry

  @kept ~s(<p>Kept <strong>bold</strong> <a href="/rooms" class="action-button">link</a></p>)

  # Everything the sanitizer refuses, each with `MARKER` where it is refused
  @refused [
    script: "<script>MARKER</script>",
    style: "<style>p{}/*MARKER*/</style>",
    iframe: ~s(<iframe src="https://example.com">MARKER</iframe>),
    object: ~s(<object data="https://example.com">MARKER</object>),
    embed: ~s(<embed src="https://example.com/MARKER">),
    form: ~s(<form action="/x"><p>MARKER</p><input name="MARKER"><button>MARKER</button></form>),
    textarea: "<textarea>MARKER</textarea>",
    select: "<select><option>MARKER</option></select>",
    svg: ~s(<svg viewBox="0 0 1 1"><circle r="1"></circle><text>MARKER</text></svg>),
    math: "<math><mi>MARKER</mi></math>",
    link: ~s(<link rel="stylesheet" href="https://example.com/MARKER">),
    meta: ~s(<meta http-equiv="refresh" content="0;url=https://example.com/MARKER">),
    base: ~s(<base href="https://example.com/MARKER">),
    event_handler: ~s|<p onclick="MARKER()">Text</p>|,
    event_handler_on_void: ~s|<img src="/a.jpg" onerror="MARKER()">|,
    event_handler_on_media: ~s|<video src="/a.mp4" onerror="MARKER()"></video>|,
    javascript_href: ~s|<a href="javascript:MARKER()">Text</a>|,
    javascript_href_encoded: ~s|<a href="java&#10;script:MARKER()">Text</a>|,
    data_src: ~s(<img src="data:image/svg+xml,MARKER">),
    formaction: ~s|<a formaction="javascript:MARKER()">Text</a>|,
    srcdoc: ~s(<div srcdoc="MARKER">Text</div>),
    style_url: ~s|<p style="background: url(MARKER)">Text</p>|,
    style_expression: ~s{<p style="width: expression(MARKER)">Text</p>},
    liveview_binding: ~s(<p phx-click="MARKER">Text</p>),
    liveview_link: ~s(<a data-phx-link="MARKER" href="/x">Text</a>)
  ]

  for {name, refused} <- @refused do
    @refused_html refused

    test "#{name}: refused, and removed with the rest kept" do
      for html <- [@kept <> @refused_html, @refused_html <> @kept, ~s(<div>#{@refused_html}#{@kept}</div>)] do
        assert RichText.sanitize_html(html) == :error, html

        rendered = RichText.render_html(html)
        refute rendered =~ "MARKER", html
        assert rendered =~ @kept, html
        # What renders is what the sanitizer takes as it is
        assert RichText.sanitize_html(rendered) == {:ok, rendered}, html
      end
    end
  end

  # Raw text in a script or a style, which no tag in it ends, and an
  # element no end tag closes
  @raw_text [
    {~s{<p>Hi</p><script></b><a href="&#106;avascript:alert(1)">Click</a></script>}, "<p>Hi</p>"},
    {"<p>Hi</p><style></b><plaintext></style><p>Rest</p>", "<p>Hi</p><p>Rest</p>"},
    {"<style>/* </p>MARKER */</style><p>Keep</p>", "<p>Keep</p>"},
    {~s|<p>Intro</p><script>document.write("<p>")</script><p>Rest</p>|, "<p>Intro</p><p>Rest</p>"},
    {"<p>Intro</p><svg><source></source>Label</svg><p>Rest</p>", "<p>Intro</p><p>Rest</p>"},
    {"<p>Intro</p><object><p>Rest</p>", "<p>Intro</p>"}
  ]

  test "a refused element is removed with what it holds, as browsers parse it" do
    for {html, rendered} <- @raw_text do
      assert RichText.render_html(html) == rendered, html
    end
  end

  test "many refused elements in a row are removed" do
    html = "<p>Intro</p>" <> String.duplicate("<object></object><p>Rest</p>", 20_000)
    {microseconds, rendered} = :timer.tc(fn -> RichText.render_html(html) end)

    assert rendered == "<p>Intro</p>" <> String.duplicate("<p>Rest</p>", 20_000)
    assert microseconds < 5_000_000
  end

  test "a refused attribute or element is removed, and the markup around it kept" do
    for {html, rendered} <- [
          {~s|<p>One <a href="/x" onclick="steal()">link</a></p><h2>Two</h2>|,
           ~s(<p>One <a href="/x">link</a></p><h2>Two</h2>)},
          {"<p>Text</p><script>alert(1)</script><p><em>More</em></p>", "<p>Text</p><p><em>More</em></p>"},
          {~s(<p class="lede" phx-mounted="x">Text</p>), ~s(<p class="lede">Text</p>)},
          {~s|<p><a href="javascript:void(0)" class="x">bad</a> good</p>|, ~s(<p><a class="x">bad</a> good</p>)},
          {~s{<p style="color: red; background: url(x)" title="T">x</p>}, ~s(<p title="T">x</p>)},
          {~s(<p>a<input value="x">b</p>), "<p>ab</p>"},
          {~s(<p>a<br>b</p><form><p>x</p><button>y</button></form><p>z</p>), "<p>a<br>b</p><p>z</p>"},
          {~s(<ul><li>One<svg><circle r="1"></circle></svg></li><li>Two</li></ul>), "<ul><li>One</li><li>Two</li></ul>"},
          {~s(<p title="a &amp; &quot;b&quot;" onclick="x">a&amp;b &lt;c&gt;</p>),
           ~s(<p title="a &amp; &quot;b&quot;">a&amp;b &lt;c&gt;</p>)}
        ] do
      assert RichText.render_html(html) == rendered, html
    end
  end

  # A comment or a refused element taken out of a `pre` leaves a line break
  # at the start of its text, which a parse drops unless it is written twice,
  # and a heading met inside a heading closes it.
  test "markup that a second parse changes keeps its markup" do
    for html <- [
          "<p>Intro</p><pre><!-- sample -->\ncode()</pre><p>Outro</p>",
          "<pre><script>x</script>\ncode()</pre>",
          "<p>Intro</p><pre>\n\n<code>code()</code></pre>",
          "<h2>Title <my-badge><h3>Sub</h3></my-badge></h2><p>Body</p>"
        ] do
      rendered = RichText.render_html(html)
      assert rendered =~ ~r{<(pre|h3)>}, html
      assert RichText.sanitize_html(rendered) == {:ok, rendered}, html
    end
  end

  test "a field read as rich text in a template keeps its markup without the refused part" do
    render = fn intro ->
      Brando.Villain.parse_and_render("{{ entry.intro }}", Brando.Villain.get_base_context(%Entry{intro: intro}))
    end

    assert render.(~s|<p>One <a href="/x" onclick="steal()">link</a></p><script>x</script><h2>Two</h2>|) ==
             render.(~s(<p>One <a href="/x">link</a></p><h2>Two</h2>))
  end

  test "a refused element in a field reaches the page by no filter" do
    for {html, rendered} <- @raw_text, filters <- ["", "| url_decode", "| url_decode | raw"] do
      render = fn intro ->
        template = "{{ entry.intro #{filters} }}"
        Brando.Villain.parse_and_render(template, Brando.Villain.get_base_context(%Entry{intro: intro}))
      end

      assert render.(html) == render.(rendered), "#{filters}: #{html}"
    end
  end
end
