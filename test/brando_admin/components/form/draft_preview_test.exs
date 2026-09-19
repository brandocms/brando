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
