defmodule Brando.FigmaTest do
  use ExUnit.Case, async: true

  alias Brando.Figma
  alias Brando.Figma.Frame
  alias Brando.Figma.Import

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
    x = Keyword.get(opts, :x, 0)

    box_node(
      %{
        "id" => id,
        "name" => name,
        "type" => "INSTANCE",
        "componentId" => opts[:component],
        "children" => [%{"id" => id <> "t", "name" => "T", "type" => "TEXT", "characters" => name}]
      },
      {x, y, width, height}
    )
  end

  defp chrome(node), do: node |> Frame.outline() |> Map.fetch!(:sections) |> Enum.map(&{&1.name, &1[:chrome]})

  # A loose rectangle with these fills, as the frame's only layer
  defp fills_node(fills) do
    frame(%{"x" => 0, "y" => 0, "width" => 1440, "height" => 900}, [
      box_node(%{"id" => "2:1", "name" => "Photo", "type" => "RECTANGLE", "fills" => fills}, {0, 0, 1344, 741})
    ])
  end

  defp fill(ref, attrs \\ %{}), do: Map.merge(%{"type" => "IMAGE", "imageRef" => ref, "scaleMode" => "FILL"}, attrs)

  defp sections(node), do: Frame.outline(node).sections

  describe "stacked image fills" do
    test "an opaque top fill over one image is one section, with the fill under it hidden" do
      node = fills_node([fill("old"), fill("new", %{"blendMode" => "NORMAL", "opacity" => 1})])

      assert [%{kind: "image", node_id: "2:1", images: [image]} = section] = sections(node)

      assert image == %{
               node_id: "2:1",
               name: "Photo",
               scale_mode: "fill",
               x: 0,
               y: 0,
               width: 1344,
               height: 741,
               hidden_fills: [%{image_ref: "old"}]
             }

      refute Map.has_key?(section, :note)

      assert [%{node_id: "2:1", image_ref: "new", section: 0, hidden_fills: [%{image_ref: "old"}]}] = Frame.images(node)
    end

    test "three opaque fills: the top one shows, cropped fills cover too" do
      crop = fill("c", %{"scaleMode" => "STRETCH", "imageTransform" => [[0.5, 0, 0.25], [0, 0.5, 0]]})
      node = fills_node([fill("a"), fill("b", %{"scaleMode" => "FIT"}), crop])

      assert [%{images: [%{scale_mode: "crop", hidden_fills: [%{image_ref: "a"}, %{image_ref: "b"}]}]}] = sections(node)
      assert [%{image_ref: "c"}] = Frame.images(node)
    end

    test "a translucent, blended or fitted top fill shows the images under it, down to one that covers, with a note" do
      node =
        fills_node([
          fill("under"),
          fill("base"),
          fill("tiled", %{"scaleMode" => "TILE"}),
          fill("soft", %{"opacity" => 0.5}),
          fill("mixed", %{"blendMode" => "MULTIPLY"})
        ])

      assert [%{images: images, note: note}] = sections(node)
      assert Enum.map(images, & &1.scale_mode) == ["fill", "tile", "fill", "fill"]
      assert [%{hidden_fills: [%{image_ref: "under"}]} | above] = images
      refute Enum.any?(above, &Map.has_key?(&1, :hidden_fills))
      assert note =~ ~s[Layer "Photo" (2:1) shows 4 images]

      assert ["base", "tiled", "soft", "mixed"] = Enum.map(Frame.images(node), & &1.image_ref)
    end

    test "a top fill that is not visible is left out: the one under it shows" do
      node = fills_node([fill("a"), fill("b"), fill("c", %{"visible" => false})])

      assert [%{images: [%{hidden_fills: [%{image_ref: "a"}]}]}] = sections(node)
      assert [%{image_ref: "b", section: 0}] = Frame.images(node)
    end

    test "a crop covers only when the image reaches every corner of the layer" do
      # Moved to the right half of the layer: its left half shows the photo under it
      moved = fill("b", %{"scaleMode" => "STRETCH", "imageTransform" => [[2, 0, -1], [0, 1, 0]]})
      node = fills_node([fill("a"), moved])

      assert [%{images: images, note: note}] = sections(node)
      assert Enum.map(images, & &1.scale_mode) == ["fill", "crop"]
      assert note =~ "shows 2 images"
      assert ["a", "b"] = Enum.map(Frame.images(node), & &1.image_ref)

      # Shrunk inside the layer
      shrunk = fill("b", %{"scaleMode" => "STRETCH", "imageTransform" => [[1.25, 0, -0.1], [0, 1.25, -0.1]]})
      assert ["a", "b"] = [fill("a"), shrunk] |> fills_node() |> Frame.images() |> Enum.map(& &1.image_ref)

      # A crop without a usable transform does not cover
      bare = fill("b", %{"scaleMode" => "STRETCH"})
      assert ["a", "b"] = [fill("a"), bare] |> fills_node() |> Frame.images() |> Enum.map(& &1.image_ref)

      # Figma's own rounding at the edges still covers
      edge = fill("b", %{"scaleMode" => "STRETCH", "imageTransform" => [[1, 0, -4.05e-5], [0, 0.5, 0.50001]]})
      assert [%{image_ref: "b", hidden_fills: [%{image_ref: "a"}]}] = [fill("a"), edge] |> fills_node() |> Frame.images()
    end

    test "an image fill at no opacity shows nothing: the one under it shows, and it is hidden" do
      node = fills_node([fill("a"), fill("ghost", %{"opacity" => 0})])

      assert [%{image_ref: "a", hidden_fills: [%{image_ref: "ghost"}]}] = Frame.images(node)
      assert [%{images: [image]} = section] = sections(node)
      refute Map.has_key?(section, :note)
      refute Map.has_key?(image, :crop)

      # Alone, the layer shows no image
      assert [] = [fill("ghost", %{"opacity" => 0.0})] |> fills_node() |> Frame.images()
    end

    test "several images showing over a covering one: the fills under it are still listed" do
      node = fills_node([fill("a"), fill("b"), fill("c", %{"opacity" => 0.5})])

      assert [%{images: [bottom, top]}] = sections(node)
      assert bottom.hidden_fills == [%{image_ref: "a"}]
      refute Map.has_key?(top, :hidden_fills)
      assert [%{image_ref: "b", hidden_fills: [_]}, %{image_ref: "c"}] = Frame.images(node)
    end

    test "solid fills do not count: an image under a solid still shows" do
      node = fills_node([fill("a"), %{"type" => "SOLID"}])
      assert [%{image_ref: "a"}] = Frame.images(node)
    end

    test "inside an instance, a stacked layer is one image of its section" do
      node =
        frame(%{"x" => 0, "y" => 0, "width" => 1440, "height" => 900}, [
          %{
            "id" => "3:1",
            "name" => "Card",
            "type" => "INSTANCE",
            "children" => [
              %{"id" => "3:2", "name" => "One", "type" => "RECTANGLE", "fills" => [fill("a"), fill("b")]},
              %{"id" => "3:3", "name" => "Two", "type" => "RECTANGLE", "fills" => [fill("c")]}
            ]
          }
        ])

      assert [%{images: [%{node_id: "3:2"}, %{node_id: "3:3"}]}] = sections(node)
    end
  end

  describe "an image's crop and rotation" do
    defp image(attrs), do: [fill("r", attrs)] |> fills_node() |> Frame.images() |> hd()

    test "a crop's imageTransform gives the part of the image shown, as fractions" do
      # The issue's example: full width, the band from 34.5% to 71% of a
      # portrait photo's height
      image = image(%{"scaleMode" => "STRETCH", "imageTransform" => [[1, 0, 0], [0, 0.3635, 0.3453]]})

      assert image.scale_mode == "crop"
      assert image.crop == %{x: 0.0, y: 0.3453, width: 1.0, height: 0.3635}
      refute Map.has_key?(image, :rotation)
    end

    test "a crop of the whole image has none" do
      image = image(%{"scaleMode" => "STRETCH", "imageTransform" => [[1, 0, 0], [0, 1, 0]]})
      assert image.scale_mode == "crop"
      refute Map.has_key?(image, :crop)
    end

    test "a rotated crop: its turn from the transform, the crop in the image as turned" do
      # A quarter turn right: the layer's top left shows the stored image's
      # bottom left. The layer shows the stored image's left half.
      image = image(%{"scaleMode" => "STRETCH", "imageTransform" => [[0, 0.5, 0], [-1, 0, 1]]})

      assert image.rotation == 90
      # The stored image's left half is the turned image's top half
      assert image.crop == %{x: 0.0, y: 0.0, width: 1.0, height: 0.5}

      assert %{rotation: 180} = image(%{"scaleMode" => "STRETCH", "imageTransform" => [[-1, 0, 1], [0, -1, 1]]})
      assert %{rotation: 270} = image(%{"scaleMode" => "STRETCH", "imageTransform" => [[0, -1, 1], [1, 0, 0]]})
    end

    test "FILL, FIT and TILE turn by the paint's rotation, clockwise as Figma's Rotate 90° button turns" do
      assert %{rotation: 90} = image(%{"rotation" => 90})
      assert %{rotation: 180} = image(%{"rotation" => 180})
      assert %{rotation: 270} = image(%{"rotation" => -90})
      assert %{rotation: 270, scale_mode: "fit"} = image(%{"rotation" => 270, "scaleMode" => "FIT"})
      # Each click of the button adds 90: Figma files hold 1170
      assert %{rotation: 90} = image(%{"rotation" => 1170})
      refute Map.has_key?(image(%{"rotation" => 360}), :rotation)
      refute Map.has_key?(image(%{"rotation" => 0}), :rotation)
    end

    test "another angle is reported as it is" do
      assert %{rotation: 12.5} = image(%{"rotation" => 12.5})
    end

    test "a mirrored crop is not read as a turn: it says it is mirrored" do
      # Flipped left to right: the layer's left edge shows the image's right
      image = image(%{"scaleMode" => "STRETCH", "imageTransform" => [[-1, 0, 1], [0, 1, 0]]})

      assert image.mirrored == true
      refute Map.has_key?(image, :rotation)
      refute Map.has_key?(image, :crop)

      # Mirrored and turned: still no rotation
      image = image(%{"scaleMode" => "STRETCH", "imageTransform" => [[0, 0.5, 0], [1, 0, 0]]})
      assert image.mirrored == true
      refute Map.has_key?(image, :rotation)
      assert image.crop == %{x: 0.0, y: 0.0, width: 0.5, height: 1.0}
    end
  end

  describe "Import.focal/1: the object-position that shows the crop" do
    test "the issue's photo: a 1344×741 layer showing 25.27%–98.78% of a 2500×1875 photo's height" do
      # y: 0.2527 / (1 - 0.7351) = 0.954 → 95; the full width → 50
      assert Import.focal(%{x: 0, y: 0.2527, width: 1, height: 0.7351}) == %{x: 50, y: 95}
    end

    test "a centred crop" do
      # 0.25 / (1 - 0.5) = 0.5
      assert Import.focal(%{x: 0.25, y: 0.25, width: 0.5, height: 0.5}) == %{x: 50, y: 50}
    end

    test "a crop of the whole image, or within rounding of it" do
      assert Import.focal(%{x: 0.0, y: 0.0, width: 1.0, height: 1.0}) == %{x: 50, y: 50}
      assert Import.focal(%{x: 0.0, y: 0.0001, width: 1.0, height: 0.9999}) == %{x: 50, y: 50}
    end

    test "a crop flush with the top or the left, and with the bottom or the right" do
      assert Import.focal(%{x: 0.0, y: 0.0, width: 0.4, height: 0.6}) == %{x: 0, y: 0}
      # 0.6 / (1 - 0.4) = 1; 0.4 / (1 - 0.6) = 1
      assert Import.focal(%{x: 0.6, y: 0.4, width: 0.4, height: 0.6}) == %{x: 100, y: 100}
    end

    test "a crop reaching past an edge is clamped" do
      # -0.1 / 0.5 = -0.2 → 0; 0.5 / (1 - 0.6) = 1.25 → 100
      assert Import.focal(%{x: -0.1, y: 0.5, width: 0.5, height: 0.6}) == %{x: 0, y: 100}
    end

    test "a turned image: the crop Frame gives is in the turned image" do
      # A quarter turn right showing the stored image's left half: the
      # turned image's top half, so the top: 0 / (1 - 0.5) = 0
      assert %{rotation: 90, crop: crop} =
               image(%{"scaleMode" => "STRETCH", "imageTransform" => [[0, 0.5, 0], [-1, 0, 1]]})

      assert Import.focal(crop) == %{x: 50, y: 0}
    end
  end

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
               images: [%{node_id: "1:11", name: "Photo", scale_mode: "fill", x: 0, y: 500, width: 1440, height: 810}],
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
            chrome_section("14", "Hovedmeny", {0, 1440, 50}),
            chrome_section("1", "Top", {200, 1440, 100}, component: "h"),
            chrome_section("2", "Main navigation", {300, 1440, 50}),
            chrome_section("3", "NavBar", {350, 1440, 50}),
            chrome_section("4", "Navigasjon", {400, 1440, 50}),
            chrome_section("5", "Global/Footer", {450, 1440, 50}),
            chrome_section("6", "Links", {2300, 1440, 300}, component: "f"),
            chrome_section("7", "Bunntekst", {2600, 1440, 200}),
            chrome_section("8", "Footer 2", {2800, 1440, 400}),
            # A menu or meny is chrome only as a short, wide bar at an edge
            chrome_section("9", "Meny", {4950, 1440, 50}),
            chrome_section("10", "Header v2", {500, 1440, 50}),
            chrome_section("11", "Hovednavigasjon", {600, 1440, 50})
          ])
          | components: names,
            component_sets: %{"fs" => %{"name" => "Footer"}}
        }

      assert chrome(node) == [
               {"Hovedmeny", "name"},
               {"Top", "component"},
               {"Main navigation", "name"},
               {"NavBar", "name"},
               {"Navigasjon", "name"},
               {"Global/Footer", "name"},
               {"Header v2", "name"},
               {"Hovednavigasjon", "name"},
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
            # Under a module's name, and a page's opening section in Norwegian
            chrome_section("12", "Case/Header", {3100, 1440, 300}),
            chrome_section("13", "Topp", {3500, 1440, 50}),
            # Flush with the bottom edge, but mostly outside the frame
            chrome_section("15", "Meny", {4950, 1440, 50}, x: 1000),
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
