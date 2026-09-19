defmodule BrandoAdmin.Components.Form.DraftPreviewTest do
  use ExUnit.Case, async: true

  alias BrandoAdmin.Components.Form.DraftPreview
  alias BrandoAdmin.Components.TextDiff

  test "compares multiline content against saved values without ref editor configuration" do
    ref = %{
      "name" => "text",
      "data" => %{
        "type" => "text",
        "data" => %{
          "text" => "<p>Introduction</p><p>Saved paragraph</p>",
          "extensions" => ["h2", "bold"],
          "footnote_module_set" => "Footnotes"
        }
      }
    }

    saved = %{"blocks" => %{"blocks" => [%{"block" => %{"refs" => [ref]}}]}}

    recovered =
      put_in(
        saved,
        ["blocks", "blocks", Access.at(0), "block", "refs", Access.at(0), "data", "data", "text"],
        "<p>Introduction</p><p>Recovered paragraph</p>"
      )

    assert [%{title: "Block 1", before: before, after: after_lines}] = DraftPreview.comparisons(saved, recovered)
    diff = TextDiff.compare(before, after_lines)
    assert diff.added == 1
    assert diff.removed == 1
    assert Enum.any?(diff.rows, &(&1.kind == :eq && &1.text == "Introduction"))
    assert Enum.any?(diff.rows, &(&1.kind == :del && &1.text == "Saved paragraph"))
    assert Enum.any?(diff.rows, &(&1.kind == :ins && &1.text == "Recovered paragraph"))
    refute Enum.any?(after_lines, &(&1.text in ["h2", "bold", "Footnotes"]))

    assert get_in(recovered, [
             "blocks",
             "blocks",
             Access.at(0),
             "block",
             "refs",
             Access.at(0),
             "data",
             "data",
             "extensions"
           ]) == ["h2", "bold"]
  end

  test "keeps removed sections, false values and equal text in different fields distinct" do
    saved = %{
      "main" => %{"title" => "Same text", "active" => false},
      "blocks" => %{"blocks" => [%{"description" => "Removed block"}]}
    }

    recovered = %{"main" => %{"subtitle" => "Same text", "active" => false}}
    sections = DraftPreview.comparisons(saved, recovered)
    entry = Enum.find(sections, &(&1.title == "Entry fields"))
    diff = TextDiff.compare(entry.before, entry.after)
    assert Enum.any?(diff.rows, &(&1.kind == :eq && &1.text == "false"))
    assert Enum.any?(diff.rows, &(&1.kind == :del && &1.text == "Same text"))
    assert Enum.any?(diff.rows, &(&1.kind == :ins && &1.text == "Same text"))
    assert %{after: [], before: [_ | _]} = Enum.find(sections, &(&1.title == "Block 1"))
    assert DraftPreview.comparisons(%{}, %{}) == []
  end

  test "shows nested recovery text, false values and media references without serialization metadata" do
    payload = %{
      "main" => %{"title" => "Campaign", "active" => false, "meta_image_id" => 42},
      "blocks" => %{
        "blocks" => [
          %{
            "id" => 10,
            "block" => %{
              "uid" => "private-block-identity",
              "module_id" => 20,
              "refs" => [%{"name" => "heading", "data" => %{"text" => "<p>Hello <strong>world</strong></p>"}}],
              "children" => [%{"vars" => [%{"key" => "name", "type" => "string", "value" => "Alex"}]}]
            }
          }
        ]
      },
      "transformers" => %{"items" => [%{"title" => "Related item"}]},
      "modules" => %{"20" => %{"code" => "Internal module template"}}
    }

    sections = DraftPreview.sections(payload)
    rows = Enum.flat_map(sections, & &1.rows)
    assert %{field: "Active", value: false} in rows
    assert %{field: "Meta image ID", value: 42} in rows
    assert %{field: "Heading › Text", value: "Hello world"} in rows
    assert %{field: "Children › 1 › Name", value: "Alex"} in rows
    assert %{field: "1 › Title", value: "Related item"} in rows
    refute Enum.any?(rows, &(&1.value in [10, 20, "private-block-identity", "Internal module template"]))
    assert get_in(payload, ["blocks", "blocks", Access.at(0), "block", "uid"]) == "private-block-identity"
  end

  test "media and related entries retain identity, names and previews across replacements and removals" do
    alias DraftPreview.References

    reference = fn kind, id, name ->
      %References{kind: kind, id: id, title: name, detail: "Preview details", thumbnail: "/media/preview.jpg"}
    end

    references = %{
      {:image, 1} => reference.(:image, 1, "cover.jpg"),
      {:image, 2} => reference.(:image, 2, "cover.jpg"),
      {:file, 3} => reference.(:file, 3, "guide.pdf"),
      {:video, 4} => reference.(:video, 4, "Launch film"),
      {:entry, 5} => reference.(:entry, 5, "Related story")
    }

    saved = %{
      "main" => %{"image_id" => 1, "file_id" => 3},
      "blocks" => %{"blocks" => [%{"refs" => [%{"name" => "hero", "image_id" => 1, "data" => %{}}]}]}
    }

    recovered = %{
      "main" => %{"image_id" => "2", "image" => nil, "video_id" => 4, "related" => [%{"identifier_id" => 5}]},
      "blocks" => %{
        "blocks" => [
          %{
            "type" => "module",
            "refs" => [%{"name" => "hero", "image_id" => 2, "data" => %{}}],
            "block_identifiers" => [%{"identifier_id" => 5}]
          }
        ]
      }
    }

    comparisons = DraftPreview.comparisons(saved, recovered, references: references)
    rows = Enum.flat_map(comparisons, &TextDiff.compare(&1.before, &1.after).rows)
    assert Enum.count(rows, &(&1.kind == :del && &1.text == "cover.jpg")) == 2
    assert Enum.count(rows, &(&1.kind == :ins && &1.text == "cover.jpg")) == 2
    assert Enum.any?(rows, &(&1.kind == :del && &1.text == "guide.pdf"))
    assert Enum.any?(rows, &(&1.kind == :ins && &1.text == "Launch film"))
    assert Enum.count(rows, &(&1.kind == :ins && &1.text == "Related story")) == 2
    assert Enum.any?(rows, &(&1[:preview] && &1.preview.thumbnail == "/media/preview.jpg"))
    assert recovered["main"]["image_id"] == "2"

    assert DraftPreview.comparisons(saved, saved, references: references)
           |> Enum.all?(&(&1.before == &1.after))
  end

  test "unavailable references remain explicit rather than disappearing from the diff" do
    [section] = DraftPreview.comparisons(%{}, %{"main" => %{"image_id" => 999}}, references: %{})
    assert Enum.any?(section.after, &(&1.text == "Unavailable Image"))
    assert Enum.any?(section.after, &(&1[:preview] && &1.preview.detail == "Reference #999"))
  end

  test "handles empty content and preserves text that is not HTML" do
    assert DraftPreview.sections(%{}) == []
    assert DraftPreview.sections(%{"blocks" => nil, "transformers" => []}) == []
    assert [%{rows: [%{value: "a < b & c > d"}]}] = DraftPreview.sections(%{"main" => %{"title" => "a < b & c > d"}})
  end

  test "previews variable values without listing their editor configuration" do
    payload = %{
      "main" => %{
        "vars" => [
          %{"key" => "show", "type" => "boolean", "value_boolean" => false},
          %{"key" => "photo", "type" => "image", "image_id" => 42},
          %{
            "key" => "align",
            "label" => "Alignment",
            "type" => "select",
            "value" => "left",
            "options" => [%{"label" => "Right", "value" => "right"}],
            "width" => "half",
            "value_boolean" => false
          }
        ]
      }
    }

    assert [%{rows: rows}] = DraftPreview.sections(payload)

    assert rows == [
             %{field: "Show", value: false},
             %{field: "Photo › Image ID", value: 42},
             %{field: "Alignment", value: "left"}
           ]
  end
end
