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
    assert render("Same content", "Same content") =~ "No changes in this preview"
    assert render("Removed content", "") =~ "1 line removed"
    assert TextDiff.compare("Removed content", "").added == 0
  end

  test "marks only headings that own changes, even after unchanged paragraphs" do
    before = [
      %{text: "Body", type: :heading},
      %{text: "Unchanged introduction"},
      %{text: "Previous ending"},
      %{text: "Color", type: :heading},
      %{text: "Blue"}
    ]

    after_lines = List.replace_at(before, 2, %{text: "Updated ending"})
    document = render(before, after_lines) |> Floki.parse_fragment!()

    assert Floki.find(document, ".is-change-heading .text-diff-text") |> Enum.map(&Floki.text/1) == ["Body"]
    assert Floki.find(document, "[data-changed=true]") != []
    assert render(before, before) =~ ~s(data-changed="false")
    assert render("", String.duplicate("a", 12_001)) =~ ~s(data-truncated="true")
  end

  test "media rows render recognizable previews and escaped details" do
    media = %{
      text: "<cover>.jpg",
      key: {:image, 1},
      type: :media,
      preview: %{kind: :image, thumbnail: "/media/cover.jpg", detail: "Image · 800 × 1000"}
    }

    document = render([], [media]) |> Floki.parse_fragment!()
    assert Floki.attribute(document, "ins img", "src") == ["/media/cover.jpg"]
    assert Floki.find(document, ".text-diff-reference-title") |> Floki.text() == "<cover>.jpg"
    assert Floki.find(document, ".text-diff-reference-detail") |> Floki.text() == "Image · 800 × 1000"
    assert Floki.find(document, "cover") == []
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

  test "keyed lines distinguish identical filenames, escape text and bound structured previews" do
    before = [%{text: "Image: cover.jpg", key: {:image, 1}, type: :media}]
    after_lines = [%{text: "Image: cover.jpg", key: {:image, 2}, type: :media}]
    diff = TextDiff.compare(before, after_lines)
    assert diff.added == 1 && diff.removed == 1
    html = render(before, after_lines)
    assert html =~ "is-media"
    refute html =~ "{:image"
    assert TextDiff.compare(before, before).added == 0

    document = render([], [%{text: "<script>unsafe</script>", key: 1}]) |> Floki.parse_fragment!()
    assert Floki.find(document, "script") == []
    assert TextDiff.compare([], List.duplicate(%{text: "a", key: nil}, 401)).truncated?
    assert TextDiff.compare([], [%{text: String.duplicate("ø", 12_001)}]).truncated?
  end
end
