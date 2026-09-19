defmodule BrandoAdmin.Components.Form.DraftReorderPreviewTest do
  use ExUnit.Case, async: true
  alias BrandoAdmin.Components.Form.DraftPreview
  alias BrandoAdmin.Components.Form.DraftPreview.References
  alias BrandoAdmin.Components.TextDiff

  defp block(uid, text) do
    %{"uid" => uid, "refs" => [%{"name" => "body", "data" => %{"text" => text}}]}
  end

  defp payload(blocks), do: %{"blocks" => %{"blocks" => Enum.map(blocks, &%{"block" => &1})}}
  defp content(sections), do: Enum.filter(sections, &(&1.kind == :content))
  defp orders(sections), do: Enum.filter(sections, &(&1.kind == :order))

  defp changed_rows(sections),
    do:
      sections
      |> content()
      |> Enum.flat_map(&TextDiff.compare(&1.before, &1.after).rows)
      |> Enum.reject(&(&1.kind == :eq))

  test "swapping blocks shows positions without replacing their contents" do
    a = block("a", "First story")
    b = block("b", "Second story")
    preview = DraftPreview.comparisons(payload([a, b]), payload([b, a]))
    assert [%{title: "Block order", moves: moves}] = orders(preview)
    assert Enum.map(moves, &{&1.title, &1.from, &1.to}) == [{"Second story", 2, 1}, {"First story", 1, 2}]
    assert changed_rows(preview) == []
  end

  test "a moved block is compared with itself so accompanying text edits remain visible" do
    a = block("a", "First story")
    b = block("b", "Before editing")
    updated = block("b", "After editing")
    preview = DraftPreview.comparisons(payload([a, b]), payload([updated, a]))
    assert length(orders(preview)) == 1
    assert Enum.map(changed_rows(preview), &{&1.kind, &1.text}) == [del: "Before editing", ins: "After editing"]
  end

  test "insertions and deletions do not mark every shifted block as moved" do
    a = block("a", "First story")
    b = block("b", "Second story")
    c = block("c", "New story")
    preview = DraftPreview.comparisons(payload([a, b]), payload([c, a]))
    assert orders(preview) == []
    rows = changed_rows(preview)
    assert Enum.any?(rows, &(&1.kind == :ins && &1.text == "New story"))
    assert Enum.any?(rows, &(&1.kind == :del && &1.text == "Second story"))
    refute Enum.any?(rows, &(&1.text == "First story"))
  end

  test "nested block moves and parent moves do not duplicate child content" do
    children = [block("a", "Child A"), block("b", "Child B")]
    parent = %{"uid" => "parent", "type" => "container", "refs" => [], "children" => children}
    other = block("other", "Other root")
    changed = %{parent | "children" => Enum.reverse(children)}
    preview = DraftPreview.comparisons(payload([parent, other]), payload([other, changed]))
    assert Enum.map(orders(preview), & &1.title) == ["Block order", "Block 2 · Block order"]
    assert changed_rows(preview) == []
  end

  defp gallery(objects, overrides \\ []) do
    payload([
      %{
        "uid" => "gallery",
        "refs" => [
          %{
            "name" => "gallery",
            "gallery" => %{"gallery_objects" => objects},
            "data" => %{"data" => %{"gallery_object_overrides" => overrides}}
          }
        ]
      }
    ])
  end

  defp refs do
    %{
      {:image, 1} => %References{kind: :image, id: 1, title: "Portrait.jpg", thumbnail: "/portrait.jpg"},
      {:image, 2} => %References{kind: :image, id: 2, title: "Landscape.jpg", thumbnail: "/landscape.jpg"}
    }
  end

  test "gallery objects and their overrides share one movement summary with thumbnails" do
    objects = [%{"id" => 10, "image_id" => 1}, %{"id" => 20, "image_id" => 2}]

    overrides = [
      %{"object_id" => "1", "object_type" => "image", "title" => "Portrait caption"},
      %{"object_id" => "2", "object_type" => "image", "title" => "Landscape caption"}
    ]

    preview =
      DraftPreview.comparisons(gallery(objects, overrides), gallery(Enum.reverse(objects), Enum.reverse(overrides)),
        references: refs()
      )

    assert [%{moves: moves}] = orders(preview)
    assert Enum.map(moves, &{&1.title, &1.from, &1.to}) == [{"Landscape.jpg", 2, 1}, {"Portrait.jpg", 1, 2}]
    assert Enum.all?(moves, & &1.thumbnail)
    assert changed_rows(preview) == []
  end

  test "override-only reordering uses typed asset identities and retains accompanying caption edits" do
    overrides = [
      %{"object_id" => "1", "object_type" => "image", "title" => "Before"},
      %{"object_id" => "2", "object_type" => "image"}
    ]

    changed = overrides |> Enum.reverse() |> List.update_at(1, &Map.put(&1, "title", "After"))
    preview = DraftPreview.comparisons(gallery([], overrides), gallery([], changed), references: refs())
    assert length(orders(preview)) == 1
    assert Enum.map(changed_rows(preview), &{&1.kind, &1.text}) == [del: "Before", ins: "After"]
  end

  test "repeated images keep distinct gallery-object identities" do
    objects = [
      %{"id" => 10, "image_id" => 1, "config" => %{"caption" => "First placement"}},
      %{"id" => 20, "image_id" => 1, "config" => %{"caption" => "Second placement"}}
    ]

    preview = DraftPreview.comparisons(gallery(objects), gallery(Enum.reverse(objects)), references: refs())
    assert [%{moves: [_, _]}] = orders(preview)
    assert changed_rows(preview) == []
  end

  test "gallery additions and replacement images are retained as changes, not moves" do
    before = [%{"id" => 10, "image_id" => 1}]
    after_rows = [%{"id" => 10, "image_id" => 2}]
    preview = DraftPreview.comparisons(gallery(before), gallery(after_rows), references: refs())
    assert orders(preview) == []
    assert Enum.any?(changed_rows(preview), &(&1.kind == :del && &1.text == "Portrait.jpg"))
    assert Enum.any?(changed_rows(preview), &(&1.kind == :ins && &1.text == "Landscape.jpg"))
  end

  test "image and video overrides with the same numeric ID remain distinct" do
    references = Map.put(refs(), {:video, 1}, %References{kind: :video, id: 1, title: "Film.mp4"})
    overrides = [%{"object_id" => "1", "object_type" => "image"}, %{"object_id" => "1", "object_type" => "video"}]

    preview =
      DraftPreview.comparisons(gallery([], overrides), gallery([], Enum.reverse(overrides)), references: references)

    assert [%{moves: moves}] = orders(preview)
    assert Enum.map(moves, & &1.title) == ["Film.mp4", "Portrait.jpg"]
    assert changed_rows(preview) == []
  end

  test "structured values changing type are not lost during collection alignment" do
    preview =
      DraftPreview.comparisons(
        %{"main" => %{"details" => %{"title" => "Original"}}},
        %{"main" => %{"details" => "Replacement"}}
      )

    assert Enum.any?(changed_rows(preview), &(&1.kind == :del && &1.text == "Original"))
    assert Enum.any?(changed_rows(preview), &(&1.kind == :ins && &1.text == "Replacement"))
  end

  test "invalid gallery values remain readable instead of being treated as collections" do
    preview = DraftPreview.comparisons(gallery([]), gallery("Invalid selection"))
    assert orders(preview) == []
    assert Enum.any?(changed_rows(preview), &(&1.kind == :ins && &1.text == "Invalid selection"))
  end
end
