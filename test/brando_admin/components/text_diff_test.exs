defmodule BrandoAdmin.Components.TextDiffTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest, only: [render_component: 2]
  alias BrandoAdmin.Components.TextDiff

  defp render(before_text, after_text, opts \\ []) do
    render_component(
      &TextDiff.diff/1,
      [id: "content-diff", label: "Blocks", before: before_text, after: after_text] ++ opts
    )
  end

  test "new entries contain additions without a fictional removed empty state" do
    html = render("", "Introduction\nNew collection", description: "New entry · all content is added")
    assert html =~ "all content is added"
    assert html =~ "2 lines added"
    document = Floki.parse_fragment!(html)
    assert Floki.find(document, "del") == []
    assert Floki.find(document, "ins") |> Enum.map(&Floki.text/1) == ["Introduction", "New collection"]
  end

  test "updates retain context and track old and new line numbers independently" do
    diff = TextDiff.compare("Heading\nOld copy\nRemove me\nFooter", "Heading\nNew copy\nFooter")
    assert diff.added == 1
    assert diff.removed == 2

    assert Enum.filter(diff.rows, &(&1.kind == :eq)) == [
             %{kind: :eq, text: "Heading", before: 1, after: 1},
             %{kind: :eq, text: "Footer", before: 4, after: 3}
           ]

    assert Enum.filter(diff.rows, &(&1.kind != :ins)) |> Enum.map(& &1.text) ==
             ["Heading", "Old copy", "Remove me", "Footer"]

    assert Enum.filter(diff.rows, &(&1.kind != :del)) |> Enum.map(& &1.text) == ["Heading", "New copy", "Footer"]
  end

  test "empty and unchanged content are distinct from deletion" do
    assert render("", "") =~ "No content"
    assert render("Same content", "Same content") =~ "No text changes in this preview"
    assert render("Removed content", "") =~ "1 line removed"
    assert TextDiff.compare("Removed content", "").added == 0
  end

  test "authored HTML is shown as escaped text" do
    html = render("", "<script>alert('unsafe')</script>\n<img src=x onerror=alert(1)>")
    document = Floki.parse_fragment!(html)
    assert Floki.find(document, "script, img") == []
    assert Floki.find(document, "ins") |> Floki.text() =~ "<script>"
  end

  test "large previews are bounded and explicitly marked as shortened" do
    lines = Enum.map_join(1..450, "\n", &"Line #{&1}")
    diff = TextDiff.compare("", lines)
    assert diff.truncated?
    assert length(diff.rows) == 400
    assert render("", lines) =~ "Preview shortened"

    assert TextDiff.compare("", String.duplicate("ø", 12_001)).truncated?
  end

  test "Norwegian labels and plural counts are translated" do
    Gettext.with_locale(Brando.Gettext, "no", fn ->
      html = render("Forrige", "Første\nAndre")
      assert html =~ "1 linje fjernet"
      assert html =~ "2 linjer lagt til"
      assert html =~ "Før → etter"
      refute html =~ "line added"
    end)
  end
end
