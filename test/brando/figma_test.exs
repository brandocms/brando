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

  defp frame(box, children) do
    %{
      file_name: "F",
      components: %{},
      component_sets: %{},
      document: %{
        "id" => "9:9",
        "name" => "Frame",
        "type" => "FRAME",
        "absoluteBoundingBox" => box,
        "children" => children
      }
    }
  end

  defp box_node(node, {x, y, width, height}),
    do: Map.put(node, "absoluteBoundingBox", %{"x" => x, "y" => y, "width" => width, "height" => height})

  describe "Frame.outline/1" do
    test "sections in reading order, with their components, texts, images and videos" do
      outline = Frame.outline(frame_node())

      assert outline.file_name == "B&Y 3.0"
      assert outline.frame == %{node_id: "1:1", name: "Case – Tipping", width: 1440, height: 3000, layout_grids: nil}

      assert [hero, intro, quote] = outline.sections

      # Auto layout keeps Figma's order; the instance's component set names
      # it. Each box is what Figma gives of it, rounded.
      assert hero == %{
               kind: "component",
               node_id: "1:10",
               name: "Hero",
               component: "Case/Image",
               variant: "Size=Full",
               x: 0,
               y: 0,
               width: 1440,
               height: 900,
               chrome: "top edge",
               texts: [%{node_id: "1:12", name: "Caption", text: "Second in the layout", x: 0, y: 0}],
               images: [%{node_id: "1:11", name: "Photo", x: 0, y: 500, width: 1440, height: 810}],
               videos: [%{node_id: "1:13", name: "Film"}]
             }

      assert %{kind: "text", node_id: "1:20", texts: [%{text: "Loose text"}]} = intro
      assert %{kind: "component", component: "Case/Quote", texts: [%{text: "Bold."}]} = quote
      refute Map.has_key?(quote, :variant)
      refute Map.has_key?(quote, :chrome)
    end

    test "boxes are relative to the frame's top left, which need not be the canvas origin" do
      node =
        frame(
          %{"x" => -500.2, "y" => 1200, "width" => 1440, "height" => 2000},
          [
            box_node(
              %{
                "id" => "2:1",
                "name" => "Row",
                "type" => "INSTANCE",
                "children" => [
                  box_node(
                    %{"id" => "2:2", "name" => "Left", "fills" => [%{"type" => "IMAGE", "imageRef" => "r"}]},
                    {-380, 1500, 360, 480.6}
                  ),
                  box_node(
                    %{"id" => "2:3", "name" => "Text", "type" => "TEXT", "characters" => "Hi"},
                    {219.8, 1620, 480, 100}
                  ),
                  box_node(%{"id" => "2:4", "name" => "Clip", "fills" => [%{"type" => "VIDEO"}]}, {520, 1500, 300, 200})
                ]
              },
              {-500.2, 1400, 1440, 600}
            )
          ]
        )

      assert [section] = Frame.outline(node).sections
      assert %{x: 0, y: 200, width: 1440, height: 600} = section
      assert [%{x: 120, y: 300, width: 360, height: 481}] = section.images
      assert [%{x: 720, y: 420, width: 480, height: 100}] = section.texts
      assert [%{x: 1020, y: 300, width: 300, height: 200}] = section.videos
      assert [%{x: 120, y: 300, image_ref: "r", section: 0}] = Frame.images(node)
    end

    test "the frame's visible layout grids, as Figma gives them" do
      hidden = %{"pattern" => "COLUMNS", "count" => 6, "visible" => false}

      grids = [
        %{
          "pattern" => "COLUMNS",
          "alignment" => "STRETCH",
          "count" => 12,
          "gutterSize" => 20,
          "offset" => 40.4,
          "sectionSize" => 92.5,
          "visible" => true,
          "color" => %{"r" => 1, "g" => 0, "b" => 0, "a" => 0.1}
        },
        %{
          "pattern" => "COLUMNS",
          "alignment" => "CENTER",
          "count" => 4,
          "gutterSize" => 10,
          "offset" => 0,
          "sectionSize" => 200
        },
        %{
          "pattern" => "ROWS",
          "alignment" => "MIN",
          "count" => -1,
          "gutterSize" => 8,
          "offset" => 0,
          "sectionSize" => 64
        },
        %{"pattern" => "GRID", "sectionSize" => 8},
        hidden
      ]

      node = put_in(frame(%{"x" => 0, "y" => 0, "width" => 1440, "height" => 900}, []).document["layoutGrids"], grids)

      assert Frame.outline(node).frame.layout_grids == [
               %{pattern: "columns", alignment: "stretch", count: 12, gutter: 20, margin: 40},
               %{pattern: "columns", alignment: "center", count: 4, gutter: 10, size: 200},
               %{pattern: "rows", alignment: "min", gutter: 8, margin: 0, size: 64},
               %{pattern: "grid", size: 8}
             ]

      hidden_only = put_in(node.document["layoutGrids"], [hidden])
      assert Frame.outline(hidden_only).frame.layout_grids == nil
    end

    test "flags sections that look like page chrome, with the reason, and keeps them" do
      names = %{"h" => %{"name" => "Site/Header"}, "f" => %{"name" => "Footer", "componentSetId" => "fs"}}

      section = fn id, name, component, y, height ->
        box_node(
          %{
            "id" => id,
            "name" => name,
            "type" => "INSTANCE",
            "componentId" => component,
            "children" => [%{"id" => id <> "t", "name" => "T", "type" => "TEXT", "characters" => name}]
          },
          {0, y, 1440, height}
        )
      end

      node =
        %{
          frame(%{"x" => 0, "y" => 0, "width" => 1440, "height" => 5000}, [
            section.("1", "Top", "h", 0, 100),
            section.("2", "Hovedmeny", nil, 100, 50),
            section.("3", "NavBar", nil, 150, 50),
            section.("4", "Toppbilde", nil, 200, 600),
            section.("5", "Case/Section header", nil, 800, 200),
            section.("6", "Toppen", nil, 1000, 100),
            section.("7", "Image row", nil, 1100, 600),
            section.("8", "Unavailable canvas", nil, 1700, 600),
            section.("9", "Links", "f", 2300, 300),
            section.("10", "Bunntekst", nil, 2600, 200),
            section.("11", "Credits", nil, 4800, 200)
          ])
          | components: names,
            component_sets: %{"fs" => %{"name" => "Site/Bottom"}}
        }

      assert node |> Frame.outline() |> Map.fetch!(:sections) |> Enum.map(&{&1.name, &1[:chrome]}) == [
               {"Top", "component"},
               {"Hovedmeny", "name"},
               {"NavBar", "name"},
               {"Toppbilde", nil},
               {"Case/Section header", "name"},
               {"Toppen", "name"},
               {"Image row", nil},
               {"Unavailable canvas", nil},
               {"Links", "component"},
               {"Bunntekst", "name"},
               {"Credits", "bottom edge"}
             ]
    end

    test "images/1 lists each visible image fill with its ref and section" do
      assert [%{node_id: "1:11", image_ref: "ref-a", section: 0}] = Frame.images(frame_node())
    end
  end
end
