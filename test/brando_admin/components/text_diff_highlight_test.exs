defmodule BrandoAdmin.Components.TextDiff.HighlightTest do
  use ExUnit.Case, async: true

  alias BrandoAdmin.Components.TextDiff.Highlight

  test "splits a Liquid template line into tags, attributes, values and expressions, text unchanged" do
    line = ~s(<a class="knapp" href="{{ lenke }}">{% t no 'Hei' %}</a> & co)
    tokens = Highlight.tokens(line, :liquid)

    assert Enum.map_join(tokens, &elem(&1, 1)) == line
    assert {"tok-tag", "<a"} in tokens
    assert {"tok-attr", "class"} in tokens
    assert {"tok-str", ~s("knapp")} in tokens
    assert {"tok-liquid", "{% t no 'Hei' %}"} in tokens
  end

  test "reads HEEx expressions with nested braces" do
    tokens = Highlight.tokens(~S(<section class={@theme}><.ref ref={%{a: 1}} /></section>), :heex)
    assert {"tok-liquid", "{@theme}"} in tokens
    assert {"tok-liquid", "{%{a: 1}}"} in tokens
    assert Enum.any?(tokens, fn {class, text} -> class == "tok-tag" and text =~ "<.ref" end)
  end

  test "escapes every token, and adds nothing between them" do
    html =
      ~s|<p title="x"><script>alert(1)</script></p>|
      |> Highlight.tokens(:html)
      |> Highlight.to_html()
      |> Phoenix.HTML.safe_to_string()

    refute html =~ "<script>"
    refute html =~ "\n"
    assert html =~ ~s|<span class="tok-tag">&gt;&lt;script&gt;</span>alert(1)|
  end
end
