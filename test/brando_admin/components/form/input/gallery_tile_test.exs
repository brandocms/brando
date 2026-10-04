defmodule BrandoAdmin.Components.Form.Input.GalleryTileTest do
  # The gallery grid (contact sheet) shared by the gallery field and the gallery
  # block: tile states, the caption/alt popover, and where its edits are stored.
  use Brando.LiveCase

  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.Galleries.Gallery, as: GallerySchema
  alias Brando.Galleries.GalleryObject
  alias Brando.MigrationTest.ProjectUpdate1
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input.Gallery
  alias BrandoAdmin.Components.Form.Input.Gallery.ImageConfig
  alias BrandoAdmin.Components.Form.Input.Gallery.Tile
  alias Ecto.Changeset
  alias Phoenix.Component

  @myself %Phoenix.LiveComponent.CID{cid: 1}

  setup %{current_user: user} do
    image =
      Factory.insert(:image,
        creator: user,
        status: :processed,
        title: "Library <title> & co",
        alt: nil
      )

    video = Factory.insert(:upload_video, creator: user, title: "Film & co")

    {:ok, user: user, image: image, video: video}
  end

  describe "Tile" do
    test "renders the position, the icon states and the peeks" do
      html =
        render_component(&Tile.tile/1, %{
          id: "tile-0",
          number: 3,
          media_type: :image,
          thumb_url: "/thumb.jpg",
          caption: Tile.caption_state("<p><strong>Rich</strong><script>x</script></p>", "Library"),
          alt: Tile.alt_state(nil, nil),
          open_caption: nil,
          open_alt: nil
        })

      doc = Floki.parse_fragment!(html)

      assert doc |> Floki.find(".gallery-tile-number") |> Floki.text() == "3"
      assert [_] = Floki.find(doc, ".gallery-tile-icon.is-set[aria-label=Caption]")
      assert [_] = Floki.find(doc, ".gallery-tile-icon.is-missing")
      assert html =~ "<strong>Rich</strong>"
      refute html =~ "<script"
      refute html =~ "No caption"
      refute html =~ "media-type-badge"
    end

    test "an empty caption is faded and a video has no alt icon" do
      html =
        render_component(&Tile.tile/1, %{
          id: "tile-1",
          number: 1,
          media_type: :video,
          caption: Tile.caption_state(nil, nil),
          open_caption: nil
        })

      doc = Floki.parse_fragment!(html)
      assert [_] = Floki.find(doc, ".gallery-tile-icon.is-empty")
      assert length(Floki.find(doc, ".gallery-tile-icon")) == 1
      assert html =~ "gallery-tile-video"
    end

    test "the library title in a peek is escaped" do
      assert Tile.caption_state(nil, "A <x> & c") == %{set?: true, html: {:safe, "A &lt;x&gt; &amp; c"}}
    end

    test "the legend counts images without alt text" do
      html = render_component(&Tile.legend/1, %{images: 4, missing_alt: 3})
      assert html =~ "No alt text — 3 of 4 images"

      html = render_component(&Tile.legend/1, %{images: 2, missing_alt: 0})
      refute html =~ "No alt text"
    end

    test "the popover's inputs are not part of the form around it" do
      html =
        render_component(&Tile.text_editor/1, %{
          id: "ed",
          kind: :alt,
          filename: "a.jpg",
          value: "Old",
          placeholder: "Library alt",
          target: @myself,
          save_event: "save_object_text",
          close_event: "close_text_editor",
          params: %{index: 0, kind: :alt}
        })

      doc = Floki.parse_fragment!(html)
      [textarea] = Floki.find(doc, "textarea")
      assert Floki.attribute(textarea, "form") == ["ed-detached"]
      assert Floki.attribute(textarea, "name") == []
      assert html =~ "Alt text"
      assert html =~ "· a.jpg"
      assert html =~ "Saved for this gallery only. Empty uses the image library&#39;s text."

      html =
        render_component(&Tile.text_editor/1, %{
          id: "ed",
          kind: :caption,
          value: "<p>A</p>",
          target: @myself,
          save_event: "s",
          close_event: "c"
        })

      [hidden] = html |> Floki.parse_fragment!() |> Floki.find("input.tiptap-text")
      assert Floki.attribute(hidden, "form") == ["ed-detached"]
      assert html =~ ~s(data-tiptap-extensions="p|bold|italic|link")
    end
  end

  describe "gallery field" do
    test "the grid renders the tile and the open popover for its object", ctx do
      object = %GalleryObject{image_id: ctx.image.id, image: ctx.image, config: %{"title" => "<p>Placed</p>"}}
      field = %{to_form(Changeset.change(object), as: "project[photos][gallery_objects][0]") | index: 0}

      html =
        render_component(&Gallery.gallery_object/1, %{
          id: "project_photos",
          gallery_objects: [object],
          gallery_object_field: field,
          parent_form_name: "project[photos]",
          preview_layout: :grid,
          text_editor: %{index: 0, kind: :caption},
          myself: @myself
        })

      doc = Floki.parse_fragment!(html)
      assert doc |> Floki.find(".gallery-tile-number") |> Floki.text() == "1"
      assert [_] = Floki.find(doc, ".gallery-text-editor--caption")
      assert [_] = Floki.find(doc, ".gallery-tile-icon.is-active")
      assert [_] = Floki.find(doc, "button.delete-object")
      assert [_] = Floki.find(doc, "button.edit-image-btn")
    end

    test "the list shows the placement caption as plain text and its alt text", ctx do
      object = %GalleryObject{
        image_id: ctx.image.id,
        image: ctx.image,
        config: %{"title" => "<p><strong>Placed</strong> caption</p>", "alt" => "Placed alt"}
      }

      field = %{to_form(Changeset.change(object), as: "project[photos][gallery_objects][0]") | index: 0}

      html =
        render_component(&Gallery.gallery_object/1, %{
          id: "project_photos",
          gallery_objects: [object],
          gallery_object_field: field,
          parent_form_name: "project[photos]",
          preview_layout: :list,
          myself: @myself
        })

      assert html =~ ~s(class="gallery-object-list-title">Placed caption<)
      assert html =~ "Placed alt"
    end

    test "saving a caption writes rich text to the image's config title", ctx do
      socket = gallery_socket(ctx)

      {:noreply, socket} =
        Gallery.handle_event(
          "save_object_text",
          %{"index" => 0, "kind" => "caption", "value" => "<p><em>New</em> caption</p>"},
          socket
        )

      assert socket.assigns.text_editor == nil
      assert put_config(0) == %{"title" => "<p><em>New</em> caption</p>", "credits" => "Kept"}
    end

    test "saving alt text stores it plain; empty removes the override", ctx do
      socket = gallery_socket(ctx)

      {:noreply, socket} =
        Gallery.handle_event("save_object_text", %{"index" => 0, "kind" => "alt", "value" => "  A <b>  "}, socket)

      assert put_config(0) == %{"alt" => "A <b>", "credits" => "Kept"}

      {:noreply, _socket} =
        Gallery.handle_event("save_object_text", %{"index" => 0, "kind" => "caption", "value" => "<p></p>"}, socket)

      assert put_config(0) == %{"alt" => "A <b>", "credits" => "Kept"}
    end

    test "a video's caption is its config caption; it has no alt text", ctx do
      socket = gallery_socket(ctx)

      {:noreply, socket} =
        Gallery.handle_event("save_object_text", %{"index" => 1, "kind" => "caption", "value" => "<p>Tour</p>"}, socket)

      assert put_config(1) == %{"caption" => "<p>Tour</p>", "autoplay" => true}

      assert {:noreply, ^socket} = Gallery.handle_event("open_text_editor", %{"index" => 1, "kind" => "alt"}, socket)
    end

    test "the view switch is the admin's choice and does not touch the gallery", ctx do
      socket = Component.assign(gallery_socket(ctx), preview_layout: :list, text_editor: %{index: 0, kind: :alt})

      {:noreply, socket} = Gallery.handle_event("set_gallery_view", %{"view" => "grid"}, socket)
      assert socket.assigns.preview_layout == :grid
      assert socket.assigns.text_editor == nil

      {:noreply, ^socket} = Gallery.handle_event("set_gallery_view", %{"view" => "tiles"}, socket)
      refute_receive {:phoenix, :send_update, _}
    end

    test "the configuration modal stores its caption as rich text", ctx do
      socket =
        %Phoenix.LiveView.Socket{}
        |> Component.assign(:gallery_component, Gallery)
        |> Component.assign(:gallery_component_id, "project_photos")
        |> Component.assign(:gallery_object_index, 0)
        |> Component.assign(:image, ctx.image)

      ImageConfig.handle_event(
        "save_config",
        %{"config" => %{"title" => ~s|<p onclick="x()"><em>A</em></p>|, "alt" => "Alt", "credits" => ""}},
        socket
      )

      assert_receive {:phoenix, :send_update,
                      {{Gallery, "project_photos"}, %{event: "update_object_config", config: config}}}

      assert config == %{"title" => "<p><em>A</em></p>", "alt" => "Alt"}

      ImageConfig.handle_event("save_config", %{"config" => %{"title" => "<p></p>"}}, socket)
      assert_receive {:phoenix, :send_update, {{Gallery, "project_photos"}, %{config: config}}}
      assert config == %{}
    end
  end

  defp gallery_socket(ctx) do
    gallery = %GallerySchema{
      config_target: "gallery:Brando.MigrationTest.ProjectUpdate1:photos",
      gallery_objects: [
        %GalleryObject{image_id: ctx.image.id, image: ctx.image, sequence: 0, config: %{"credits" => "Kept"}},
        %GalleryObject{video_id: ctx.video.id, video: ctx.video, sequence: 1, config: %{"autoplay" => true}}
      ]
    }

    form = to_form(Changeset.change(%ProjectUpdate1{photos: gallery}), as: "project")

    %Phoenix.LiveView.Socket{}
    |> Component.assign(:field, form[:photos])
    |> Component.assign(:path, [])
    |> Component.assign(:form_id, "project_form")
    |> Component.assign(:gallery_objects, gallery.gallery_objects)
    |> Component.assign(:text_editor, %{index: 0, kind: :caption})
  end

  defp put_config(index) do
    assert_receive {:phoenix, :send_update, {{Form, "project_form"}, %{action: :put_gallery, gallery: gallery}}}
    gallery.gallery_objects |> Enum.at(index) |> Map.get(:config)
  end
end
