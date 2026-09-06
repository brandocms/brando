defmodule Brando.Villain.FootnotesTest do
  use ExUnit.Case, async: true
  alias Brando.Villain.Footnotes

  defp marker(uid), do: ~s(<sup data-footnote-uid="#{uid}">•</sup>)
  defp definition(uid, html), do: ~s(<template data-brando-footnote="#{uid}">#{html}</template>)

  test "numbers follow rendered order, with one note and distinct backlinks for repeated markers" do
    html =
      "<article><p>First#{marker("b")}</p><aside>Next#{marker("a")}</aside><p>Again#{marker("b")}</p></article>" <>
        definition("a", "<p>A source</p>") <> definition("b", "<p>B source</p><figure>Media</figure>")

    result = Footnotes.render(html)
    assert Enum.map(result.notes, &{&1.uid, &1.number}) == [{"b", 1}, {"a", 2}]
    assert length(hd(result.notes).reference_ids) == 2
    assert hd(result.notes).html =~ "<figure>Media</figure>"
    assert length(Floki.find(Floki.parse_fragment!(result.html), "[role=doc-noteref]")) == 3
    refute result.html =~ "<template"
    output = Footnotes.to_html(result)
    assert output =~ ~s(role="doc-endnotes")
    assert length(Floki.find(Floki.parse_fragment!(output), "[role=doc-backlink]")) == 3
  end

  test "unused definitions do not emit notes or consume numbers" do
    result =
      Footnotes.render("<p>Body#{marker("used")}</p>" <> definition("unused", "Hidden") <> definition("used", "Visible"))

    assert [%{uid: "used", number: 1}] = result.notes
    refute Footnotes.to_html(result) =~ "Hidden"
  end

  test "independently cached results can be combined and renumbered" do
    first = Footnotes.render(marker("a") <> definition("a", "First")) |> Footnotes.to_html()
    second = Footnotes.render(marker("b") <> definition("b", "Second")) |> Footnotes.to_html()
    combined = Footnotes.render(second <> first, scope: "combined")
    assert Enum.map(combined.notes, &{&1.uid, &1.number}) == [{"b", 1}, {"a", 2}]
    tree = combined |> Footnotes.to_html() |> Floki.parse_fragment!()
    ids = Floki.attribute(tree, "[id]", "id")
    assert length(ids) == length(Enum.uniq(ids))
    assert length(Floki.find(tree, "[data-brando-footnotes]")) == 1
  end

  test "scope and note identity cannot inject markup or collide after punctuation removal" do
    result =
      Footnotes.render(marker("a-b") <> marker("ab") <> definition("a-b", "One") <> definition("ab", "Two"),
        scope: "\" onclick=\"alert(1)"
      )

    assert length(Enum.uniq(Enum.map(result.notes, & &1.id))) == 2
    refute result.html =~ "onclick"
  end

  test "missing references degrade visibly and scripts are not traversed as content" do
    result = Footnotes.render("<p>Source#{marker("missing")}</p><script>const note = 'data-footnote-uid';</script>")
    assert result.notes == []
    assert result.html =~ "footnote-unresolved"
    assert result.html =~ "const note"
  end

  test "ordinary HTML is returned byte-for-byte without parsing" do
    html = "<div data-x='y'>Existing &amp; unchanged</div>"
    assert Footnotes.render(html) == %{html: html, notes: []}
  end
end
