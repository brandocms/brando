defmodule BrandoAdmin.Components.Form.DraftPreviewTest do
  use ExUnit.Case, async: true

  alias BrandoAdmin.Components.Form.DraftPreview

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
