defmodule BrandoAdmin.Components.Assets.MediaFieldButtonsTest do
  # One button pattern for every media field (#3093): Upload keeps its label,
  # every other source is its icon alone. The icon's label stays its accessible
  # name (visually hidden) and is the shared tooltip's text, with no `title`
  # to show a second, native tooltip.
  use Brando.ConnCase, async: true

  import Phoenix.Component, only: [to_form: 1]
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1, render_component: 2]

  alias Brando.MigrationTest.ProjectUpdate1
  alias BrandoAdmin.Components.Assets.MediaField
  alias BrandoAdmin.Components.Form.Input.Gallery

  @image %Brando.Images.Image{
    id: 1,
    status: :processed,
    path: "images/a.jpg",
    width: 10,
    height: 10,
    alt: %{},
    sizes: %{"small" => "images/small/a.jpg", "xlarge" => "images/xlarge/a.jpg"}
  }

  # The field's first button group: the sources of an empty field, or
  # Configure and the sources of a filled one
  @group ".media-field-actions > .media-field-split:first-child > button"

  defp render_field(type, asset, extra \\ %{}) do
    %{
      id: "f",
      type: type,
      asset: asset,
      kind: "entry_field",
      presentation: :field,
      browse: %Phoenix.LiveView.JS{},
      configure: %Phoenix.LiveView.JS{},
      __changed__: nil
    }
    |> Map.merge(extra)
    |> MediaField.field()
    |> rendered_to_string()
    |> LazyHTML.from_fragment()
  end

  defp buttons(doc, selector) do
    doc
    |> LazyHTML.query(selector)
    |> Enum.map(fn button ->
      hidden = button |> LazyHTML.query(".media-button-label") |> LazyHTML.text()

      %{
        icon_only?: button |> LazyHTML.attribute("class") |> hd() |> String.contains?("media-button--icon"),
        # What a screen reader names it: the hidden label, or the visible text
        name: if(hidden == "", do: button |> LazyHTML.text() |> String.trim(), else: hidden),
        tooltip: button |> LazyHTML.attribute("data-tooltip") |> List.first(),
        title: button |> LazyHTML.attribute("title") |> List.first()
      }
    end)
  end

  defp assert_icon_only(button, name) do
    assert %{icon_only?: true, name: ^name, tooltip: ^name, title: nil} = button
  end

  defp assert_labelled(button, name) do
    assert %{icon_only?: false, name: ^name, tooltip: nil, title: nil} = button
  end

  test "an empty image field: Upload with its label, then the library as an icon" do
    assert [upload, library] = :image |> render_field(nil) |> buttons(@group)
    assert_labelled(upload, "Upload")
    assert_icon_only(library, "Select image")
  end

  test "an empty file field: Upload with its label, then the library as an icon" do
    assert [upload, library] = :file |> render_field(nil) |> buttons(@group)
    assert_labelled(upload, "Upload")
    assert_icon_only(library, "Select file")
  end

  # The test config has no video upload strategy, so the library leads the
  # group and keeps its label; adding by URL is still an icon.
  test "an empty video field without uploads: the library leads, the URL is an icon" do
    assert [library, url] = :video |> render_field(nil, %{link: %Phoenix.LiveView.JS{}}) |> buttons(@group)
    assert_labelled(library, "Select video")
    assert_icon_only(url, "Add from URL")
  end

  test "a filled field: Configure, then the same sources as icons in the same order" do
    assert [configure, upload, library] = :image |> render_field(@image) |> buttons(@group)
    assert_labelled(configure, "Configure")
    assert_icon_only(upload, "Upload replacement")
    assert_icon_only(library, "Select image")
  end

  test "a filled video field offers adding by URL after the library" do
    video = %Brando.Videos.Video{id: 1, type: :external_file, title: "Clip", source_url: "https://example.com/a.mp4"}

    assert [configure, library, url] = :video |> render_field(video, %{link: %Phoenix.LiveView.JS{}}) |> buttons(@group)
    assert_labelled(configure, "Configure")
    assert_icon_only(library, "Select video")
    assert_icon_only(url, "Add from URL")
  end

  test "an empty gallery field: Upload with its label, images and videos as icons" do
    form = to_form(Ecto.Changeset.change(%ProjectUpdate1{}))

    doc =
      Gallery
      |> render_component(id: "gallery", field: form[:photos], label: "Photos", opts: [], form_id: "project_form")
      |> LazyHTML.from_fragment()

    assert [upload, images, videos] = buttons(doc, ".gallery-actions .segmented-buttons > button")
    assert_labelled(upload, "Upload")
    assert_icon_only(images, "Select images")
    assert_icon_only(videos, "Select videos")
  end

  test "the Norwegian labels name the icons" do
    Gettext.with_locale(Brando.Gettext, "no", fn ->
      assert [_upload, library] = :image |> render_field(nil) |> buttons(@group)
      assert_icon_only(library, "Velg bilde")
    end)
  end
end
