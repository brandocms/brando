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

  # An instance with a text, at x 0
  defp chrome_section(id, name, {y, width, height}, opts \\ []) do
    box_node(
      %{
        "id" => id,
        "name" => name,
        "type" => "INSTANCE",
        "componentId" => opts[:component],
        "children" => [%{"id" => id <> "t", "name" => "T", "type" => "TEXT", "characters" => name}]
      },
      {0, y, width, height}
    )
  end

  defp chrome(node), do: node |> Frame.outline() |> Map.fetch!(:sections) |> Enum.map(&{&1.name, &1[:chrome]})

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
        %{"pattern" => "GRID"},
        hidden
      ]

      node = put_in(frame(%{"x" => 0, "y" => 0, "width" => 1440, "height" => 900}, []).document["layoutGrids"], grids)

      assert Frame.outline(node).frame.layout_grids == [
               %{pattern: "columns", alignment: "stretch", count: 12, gutter: 20, margin: 40},
               %{pattern: "columns", alignment: "center", count: 4, gutter: 10, size: 200},
               %{pattern: "rows", alignment: "min", gutter: 8, margin: 0, size: 64},
               %{pattern: "grid", size: 8},
               %{pattern: "grid"}
             ]

      hidden_only = put_in(node.document["layoutGrids"], [hidden])
      assert Frame.outline(hidden_only).frame.layout_grids == nil
    end

    test "flags sections named like page chrome, with the reason, and keeps them" do
      names = %{
        "h" => %{"name" => "Site/Header"},
        "f" => %{"name" => "Theme=Dark", "componentSetId" => "fs"}
      }

      node =
        %{
          frame(%{"x" => 0, "y" => 0, "width" => 1440, "height" => 5000}, [
            chrome_section("1", "Top", {200, 1440, 100}, component: "h"),
            chrome_section("2", "Main navigation", {300, 1440, 50}),
            chrome_section("3", "NavBar", {350, 1440, 50}),
            chrome_section("4", "Navigasjon", {400, 1440, 50}),
            chrome_section("5", "Topp", {450, 1440, 50}),
            chrome_section("6", "Links", {2300, 1440, 300}, component: "f"),
            chrome_section("7", "Bunntekst", {2600, 1440, 200}),
            chrome_section("8", "Footer 2", {2800, 1440, 400}),
            # A menu or meny is chrome only as a short, wide bar at an edge
            chrome_section("9", "Meny", {4950, 1440, 50})
          ])
          | components: names,
            component_sets: %{"fs" => %{"name" => "Footer"}}
        }

      assert chrome(node) == [
               {"Top", "component"},
               {"Main navigation", "name"},
               {"NavBar", "name"},
               {"Navigasjon", "name"},
               {"Topp", "name"},
               {"Links", "component"},
               {"Bunntekst", "name"},
               {"Footer 2", "name"},
               {"Meny", "name"}
             ]
    end

    test "does not flag content by its name" do
      node =
        %{
          frame(%{"x" => 0, "y" => 0, "width" => 1440, "height" => 5000}, [
            chrome_section("1", "Navn", {100, 1440, 100}),
            chrome_section("2", "Case/Section header", {200, 1440, 200}),
            chrome_section("3", "Button", {400, 1440, 100}, component: "navy"),
            # A restaurant's menu: tall, and not at an edge
            chrome_section("4", "Meny", {500, 1440, 1200}),
            chrome_section("5", "Meny", {1700, 1440, 100}),
            chrome_section("6", "Toppbilde", {1800, 1440, 600}),
            chrome_section("7", "Lunsjmeny", {2400, 1440, 600}),
            chrome_section("8", "Subheader", {3000, 1440, 100}),
            # Figma names a text layer after its text
            box_node(
              %{"id" => "9", "name" => "Se hele menyen", "type" => "TEXT", "characters" => "Se hele menyen"},
              {0, 3200, 400, 40}
            ),
            box_node(%{"id" => "10", "name" => "Header", "type" => "TEXT", "characters" => "Header"}, {0, 3300, 400, 40}),
            # An image-only section has no texts to check before leaving it out
            box_node(
              %{
                "id" => "11",
                "name" => "Header",
                "type" => "INSTANCE",
                "children" => [%{"id" => "11i", "name" => "Photo", "fills" => [%{"type" => "IMAGE", "imageRef" => "r"}]}]
              },
              {0, 3400, 1440, 600}
            )
          ])
          | components: %{"navy" => %{"name" => "Color=Navy", "componentSetId" => "b"}},
            component_sets: %{"b" => %{"name" => "Case/Button"}}
        }

      assert Enum.all?(chrome(node), &match?({_name, nil}, &1)), inspect(chrome(node))
    end

    test "does not flag a section for sitting at the frame's edge" do
      hero = chrome_section("1", "Case/Image", {0, 1440, 800})
      quote = chrome_section("2", "Case/Quote", {800, 1440, 200})

      # The first and last child of a vertical auto layout without padding
      auto =
        frame(%{"x" => 0, "y" => 0, "width" => 1440, "height" => 1000}, [hero, quote])
        |> put_in([:document, "layoutMode"], "VERTICAL")

      assert chrome(auto) == [{"Case/Image", nil}, {"Case/Quote", nil}]

      # Loose layers in the top row
      loose =
        frame(%{"x" => 0, "y" => 0, "width" => 1440, "height" => 1000}, [
          box_node(%{"id" => "1", "name" => "Topp", "type" => "TEXT", "characters" => "Topp"}, {0, 0, 1440, 40}),
          box_node(
            %{"id" => "2", "name" => "Header", "fills" => [%{"type" => "IMAGE", "imageRef" => "r"}]},
            {0, 0, 1440, 90}
          ),
          quote
        ])

      assert Enum.all?(chrome(loose), &match?({_name, nil}, &1))

      # Sections past the frame's edges, named like a menu bar
      overflow =
        frame(%{"x" => 0, "y" => 0, "width" => 1440, "height" => 1000}, [
          chrome_section("1", "Meny", {-200, 1440, 100}),
          chrome_section("2", "Case/Text", {300, 1440, 200}),
          chrome_section("3", "Meny", {950, 1440, 100})
        ])

      assert Enum.all?(chrome(overflow), &match?({_name, nil}, &1))
    end

    test "does not flag the frame itself" do
      # An image fill on the frame
      filled =
        frame(%{"x" => 0, "y" => 0, "width" => 1440, "height" => 1000}, [
          chrome_section("1", "Case/Quote", {200, 1440, 200})
        ])
        |> put_in([:document, "name"], "Header")
        |> put_in([:document, "fills"], [%{"type" => "IMAGE", "imageRef" => "bg"}])

      assert chrome(filled) == [{"Header", nil}, {"Case/Quote", nil}]

      # A selected node that is an instance
      instance =
        frame(%{"x" => 0, "y" => 0, "width" => 1440, "height" => 100}, [
          %{"id" => "t", "name" => "Link", "type" => "TEXT", "characters" => "Om oss"}
        ])
        |> put_in([:document, "type"], "INSTANCE")
        |> put_in([:document, "name"], "Site header")

      assert chrome(instance) == [{"Site header", nil}]
    end

    test "images/1 lists each visible image fill with its ref and section" do
      assert [%{node_id: "1:11", image_ref: "ref-a", section: 0}] = Frame.images(frame_node())
    end
  end
end
