defmodule Brando.FigmaTest do
  use ExUnit.Case, async: true

  alias Brando.Figma
  alias Brando.Figma.Frame

  describe "parse_url/1" do
    test "takes the file and node of a design link, with the node id as the API writes it" do
      url = "https://www.figma.com/design/35BOzFjfvJHJM6Wm50E3wA/B-Y-3.0-%E2%80%93-shared?node-id=2950-4703&t=Kqm5bk-11"
      assert Figma.parse_url(url) == {:ok, %{file_key: "35BOzFjfvJHJM6Wm50E3wA", node_id: "2950:4703"}}

      assert {:ok, %{file_key: "35BOzFjfvJHJM6Wm50E3wA"}} =
               Figma.parse_url("https://figma.com/file/35BOzFjfvJHJM6Wm50E3wA/Name?node-id=1-2")
    end

    test "a branch link names the branch's file" do
      url = "https://www.figma.com/design/35BOzFjfvJHJM6Wm50E3wA/branch/AbCdEfGhIjKlMn/Name?node-id=1-2"
      assert {:ok, %{file_key: "AbCdEfGhIjKlMn", node_id: "1:2"}} = Figma.parse_url(url)
    end

    test "refuses other hosts, links without a node, and odd node ids" do
      assert {:error, "That is not a Figma link (figma.com)."} =
               Figma.parse_url("https://figma.com.evil.test/design/35BOzFjfvJHJM6Wm50E3wA/x?node-id=1-2")

      assert {:error, "The link names no frame." <> _} =
               Figma.parse_url("https://www.figma.com/design/35BOzFjfvJHJM6Wm50E3wA/Name")

      assert {:error, _} = Figma.parse_url("https://www.figma.com/design/35BOzFjfvJHJM6Wm50E3wA/x?node-id=../../me")
      assert {:error, _} = Figma.parse_url("https://www.figma.com/design/../x?node-id=1-2")
      assert {:error, _} = Figma.parse_url(nil)
    end
  end

  # A case frame laid out freely (sorted by position), holding an auto-layout
  # instance, a loose text and a hidden layer
  defp frame_node do
    %{
      file_name: "B&Y 3.0",
      components: %{
        "c1" => %{"name" => "Size=Full", "componentSetId" => "s1"},
        "c2" => %{"name" => "Case/Quote"}
      },
      component_sets: %{"s1" => %{"name" => "Case/Image"}},
      document: %{
        "id" => "1:1",
        "name" => "Case – Tipping",
        "type" => "FRAME",
        "absoluteBoundingBox" => %{"x" => 0, "y" => 0, "width" => 1440, "height" => 3000},
        "children" => [
          %{
            "id" => "1:30",
            "name" => "Quote",
            "type" => "INSTANCE",
            "componentId" => "c2",
            "absoluteBoundingBox" => %{"x" => 0, "y" => 2000, "width" => 1440, "height" => 300},
            "children" => [%{"id" => "1:31", "name" => "Quote text", "type" => "TEXT", "characters" => "Bold."}]
          },
          %{
            "id" => "1:10",
            "name" => "Hero",
            "type" => "INSTANCE",
            "componentId" => "c1",
            "layoutMode" => "VERTICAL",
            "absoluteBoundingBox" => %{"x" => 0, "y" => 0, "width" => 1440, "height" => 900},
            "children" => [
              %{
                "id" => "1:12",
                "name" => "Caption",
                "type" => "TEXT",
                "characters" => "Second in the layout",
                "absoluteBoundingBox" => %{"x" => 0, "y" => 0}
              },
              %{
                "id" => "1:11",
                "name" => "Photo",
                "type" => "RECTANGLE",
                "fills" => [
                  %{"type" => "SOLID"},
                  %{"type" => "IMAGE", "imageRef" => "ref-a"},
                  %{"type" => "IMAGE", "imageRef" => "ref-hidden", "visible" => false}
                ],
                "absoluteBoundingBox" => %{"x" => 0, "y" => 500, "width" => 1440.4, "height" => 810}
              },
              %{"id" => "1:13", "name" => "Film", "type" => "RECTANGLE", "fills" => [%{"type" => "VIDEO"}]}
            ]
          },
          %{
            "id" => "1:20",
            "name" => "Intro",
            "type" => "TEXT",
            "characters" => "Loose text",
            "absoluteBoundingBox" => %{"x" => 0, "y" => 1000}
          },
          %{
            "id" => "1:40",
            "name" => "Draft",
            "type" => "TEXT",
            "visible" => false,
            "characters" => "Hidden",
            "absoluteBoundingBox" => %{"x" => 0, "y" => 1500}
          }
        ]
      }
    }
  end

  describe "Frame.outline/1" do
    test "sections in reading order, with their components, texts, images and videos" do
      outline = Frame.outline(frame_node())

      assert outline.file_name == "B&Y 3.0"
      assert outline.frame == %{node_id: "1:1", name: "Case – Tipping", width: 1440, height: 3000}

      assert [hero, intro, quote] = outline.sections

      # Auto layout keeps Figma's order; the instance's component set names it
      assert hero == %{
               kind: "component",
               node_id: "1:10",
               name: "Hero",
               component: "Case/Image",
               variant: "Size=Full",
               texts: [%{node_id: "1:12", name: "Caption", text: "Second in the layout"}],
               images: [%{node_id: "1:11", name: "Photo", width: 1440, height: 810}],
               videos: [%{node_id: "1:13", name: "Film"}]
             }

      assert %{kind: "text", node_id: "1:20", texts: [%{text: "Loose text"}]} = intro
      assert %{kind: "component", component: "Case/Quote", texts: [%{text: "Bold."}]} = quote
      refute Map.has_key?(quote, :variant)
    end

    test "images/1 lists each visible image fill with its ref and section" do
      assert [%{node_id: "1:11", image_ref: "ref-a", section: 0}] = Frame.images(frame_node())
    end
  end
end
