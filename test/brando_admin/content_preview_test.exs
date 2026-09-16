defmodule BrandoAdmin.ContentPreviewTest do
  use ExUnit.Case, async: true
  alias BrandoAdmin.ContentPreview
  alias BrandoAdmin.Components.TextDiff

  defp block(title, refs \\ [], extra \\ %{}),
    do: Map.merge(%{"description" => title, "refs" => refs}, extra)

  defp image(id, path, extra \\ %{}), do: Map.merge(%{"id" => id, "path" => path}, extra)

  defp picture(image, overrides \\ %{}),
    do: %{"name" => "cover", "image_id" => image["id"], "image" => image, "data" => %{"data" => overrides}}

  defp text(rows), do: Enum.map(rows, & &1.text)
  defp changes(rows, kind), do: rows |> Enum.filter(&(&1.kind == kind)) |> text()

  test "saved media associations and mapped portable assets compare by destination identity" do
    image = %Brando.Images.Image{id: 51, path: "images/courtyard.jpg", alt: "Courtyard"}

    saved = %Brando.Content.Block{
      description: "Hero",
      refs: [%Brando.Content.Ref{name: "cover", image_id: 51, image: image}],
      vars: [],
      table_rows: [],
      children: []
    }

    deps = %{"image:7" => %{"kind" => "image", "data" => %{"path" => "source/old.jpg"}}}
    incoming = block("Hero", [%{"name" => "cover", "image_id" => "image:7"}])
    assets = ContentPreview.bundle_assets(deps, %{"image:7" => image})
    before = ContentPreview.lines([saved])
    after_lines = ContentPreview.lines([incoming], assets)
    assert before == after_lines
    assert text(before) == ["Hero", "Image · cover: courtyard.jpg", "Alt text: Courtyard"]
    assert TextDiff.compare(before, after_lines).added == 0
  end

  test "different assets with the same filename still produce replacement rows without leaking IDs" do
    before = ContentPreview.lines([block("Hero", [picture(image(1, "first/cover.jpg"))])])
    after_lines = ContentPreview.lines([block("Hero", [picture(image(2, "second/cover.jpg"))])])
    diff = TextDiff.compare(before, after_lines)
    assert changes(diff.rows, :del) == ["Image · cover: cover.jpg"]
    assert changes(diff.rows, :ins) == ["Image · cover: cover.jpg"]
    refute inspect(text(diff.rows)) =~ "first/"
  end

  test "moving media between blocks marks both positions, including repeated placements" do
    cover = picture(image(1, "images/courtyard.jpg"))
    before = ContentPreview.lines([block("Hero", [cover]), block("Story"), block("Footer", [cover])])
    after_lines = ContentPreview.lines([block("Hero"), block("Story", [cover]), block("Footer", [cover])])
    diff = TextDiff.compare(before, after_lines)
    assert changes(diff.rows, :del) == ["Image · cover: courtyard.jpg"]
    assert changes(diff.rows, :ins) == ["Image · cover: courtyard.jpg"]
    assert Enum.count(diff.rows, &(&1.kind == :eq && &1.text == "Image · cover: courtyard.jpg")) == 1
  end

  test "caption overrides and focal points are visible, while generated data stays out" do
    media =
      image(1, "images/house.jpg", %{
        "alt" => "Default",
        "focal" => %{"x" => 35, "y" => 70},
        "sizes" => %{"thumb" => "secret.jpg"}
      })

    before = ContentPreview.lines([block("Hero", [picture(media)])])

    after_lines =
      ContentPreview.lines([
        block("Hero", [picture(media, %{"alt" => "Garden", "link" => "/visit", "title" => "A quiet place"})])
      ])

    diff = TextDiff.compare(before, after_lines)
    assert changes(diff.rows, :del) == ["Alt text: Default"]
    assert changes(diff.rows, :ins) == ["Title: A quiet place", "Alt text: Garden", "Link: /visit"]
    assert "Focal point: 35% / 70%" in text(after_lines)
    refute Enum.join(text(after_lines)) =~ "secret"
  end

  test "gallery order and placement overrides survive portable object identities" do
    deps = %{
      "gallery:1" => %{
        "kind" => "gallery",
        "objects" => [
          %{
            "key" => "gallery_object:10",
            "image_id" => "image:1",
            "sequence" => 0,
            "config" => %{"alt" => "Gallery default"}
          },
          %{"key" => "gallery_object:20", "image_id" => "image:2", "sequence" => 1}
        ]
      },
      "image:1" => %{"kind" => "image", "data" => %{"path" => "one.jpg"}},
      "image:2" => %{"kind" => "image", "data" => %{"path" => "two.jpg"}}
    }

    ref = %{
      "name" => "Photos",
      "gallery_id" => "gallery:1",
      "data" => %{
        "data" => %{
          "gallery_object_overrides" => [
            %{"object_id" => "gallery_object:10", "alt" => "Placement caption", "use_default_alt" => false},
            %{"object_id" => "gallery_object:20", "alt" => "Ignored caption", "use_default_alt" => true}
          ]
        }
      }
    }

    assets = ContentPreview.bundle_assets(deps, %{})
    before = ContentPreview.lines([block("Collection", [ref])], assets)

    assert text(before) == [
             "Collection",
             "Gallery · Photos",
             "Image: one.jpg",
             "Alt text: Placement caption",
             "Image: two.jpg"
           ]

    deps = put_in(deps, ["gallery:1", "objects", Access.at(0), "sequence"], 2)
    after_lines = ContentPreview.lines([block("Collection", [ref])], ContentPreview.bundle_assets(deps, %{}))
    diff = TextDiff.compare(before, after_lines)
    assert diff.added > 0 && diff.removed > 0
    assert hd(tl(tl(text(after_lines)))) == "Image: two.jpg"
  end

  test "files, uploaded and external videos, posters, table vars and nested blocks are readable" do
    deps = %{
      "file:1" => %{"kind" => "file", "data" => %{"filename" => "collection.pdf"}},
      "file:2" => %{"kind" => "file", "data" => %{"filename" => "tour.mp4"}},
      "image:3" => %{"kind" => "image", "data" => %{"path" => "poster.jpg"}},
      "video:4" => %{"kind" => "video", "data" => %{"file_id" => "file:2", "thumbnail_id" => "image:3"}},
      "video:5" => %{"kind" => "video", "data" => %{"source_url" => "https://example.com/tour"}}
    }

    content =
      block("Collection", [%{"name" => "Film", "video_id" => "video:4"}], %{
        "table_rows" => [%{"vars" => [%{"label" => "Brochure", "file_id" => "file:1"}]}],
        "children" => [block("Interview", [%{"name" => "Clip", "video_id" => "video:5"}])]
      })

    lines = ContentPreview.lines([content], ContentPreview.bundle_assets(deps, %{})) |> text()
    assert "Video · Film: tour.mp4" in lines
    assert "Image · Poster: poster.jpg" in lines
    assert "File · Brochure: collection.pdf" in lines
    assert "Video · Clip: https://example.com/tour" in lines
    assert "Row 1" in lines
    assert "Interview" in lines
  end

  test "unavailable media remains visible without technical identifiers" do
    lines = ContentPreview.lines([block("Hero", [%{"name" => "cover", "image_id" => "image:123"}])])
    assert text(lines) == ["Hero", "Image · cover: Unavailable media"]
  end

  test "rich text keeps paragraphs and line breaks without splitting inline emphasis" do
    ref = %{"data" => %{"data" => %{"text" => "<p>A <strong>quiet</strong> place.</p><p>Visit<br>today.</p>"}}}
    assert ContentPreview.lines([block("Story", [ref])]) |> text() == ["Story", "A quiet place.", "Visit", "today."]

    media = image(1, "house.jpg", %{"alt" => "Default description"})

    assert ContentPreview.lines([block("Hero", [picture(media, %{"alt" => ""})])]) ==
             ContentPreview.lines([block("Hero", [picture(media)])])
  end

  test "media labels and metadata are translated to Norwegian" do
    Gettext.with_locale(Brando.Gettext, "no", fn ->
      lines = ContentPreview.lines([block("Forside", [picture(image(1, "hus.jpg", %{"alt" => "Hage"}))])])
      assert "Bilde · cover: hus.jpg" in text(lines)
      assert "Alternativ tekst: Hage" in text(lines)
    end)
  end
end
