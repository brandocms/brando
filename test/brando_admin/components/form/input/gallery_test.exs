defmodule BrandoAdmin.Components.Form.Input.GalleryTest do
  # Regression coverage for D4 and D5 in the form audit.
  #
  # D4 — the component addressed the entry form as
  # `"#{changeset.data.__struct__.__naming__().singular}_form"`. That changeset
  # belongs to whatever schema OWNS the gallery field, so for a gallery on a
  # nested (subform) record it named a component that does not exist and every
  # picker selection silently went nowhere. It also shipped a replacement
  # changeset for that nested record — which, had the id ever matched, would
  # have overwritten the entry's changeset with a subrecord's. The upload path
  # never had either problem because it delivers `path` + gallery instead.
  #
  # D5 — `gallery_objects` / `selected_images` / `selected_videos` were cached
  # with `assign_new`, so a gallery mutated anywhere else (an upload delivered
  # to the entry form, a revision restore) never reached the UI. They now
  # re-derive from the changeset every update, carrying previously-loaded
  # `:image` / `:video` across by id so the thumbnails survive the round trip.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.Component, only: [to_form: 1, to_form: 2]

  alias Brando.Factory
  alias Brando.Galleries
  alias Brando.Galleries.GalleryObject
  alias Brando.MigrationTest.ProjectUpdate1
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input.Gallery
  alias Ecto.Changeset
  alias Phoenix.Component

  setup do
    user = Factory.insert(:random_user)
    {:ok, user: user, image: Factory.insert(:image, creator: user)}
  end

  defp gallery_socket(form, path, extra) do
    socket =
      %Phoenix.LiveView.Socket{}
      |> Component.assign(:field, form[:photos])
      |> Component.assign(:path, path)
      |> Component.assign(:gallery_objects, [])
      |> Component.assign(:selected_images, [])
      |> Component.assign(:selected_videos, [])
      |> Component.assign(extra)

    %{socket | assigns: Map.put(socket.assigns, :myself, %Phoenix.LiveComponent.CID{cid: 1})}
  end

  describe "D4 — picker writes reach the entry form" do
    test "a top-level gallery ships path + key to the entry form", ctx do
      form = to_form(Changeset.change(%ProjectUpdate1{}))

      socket = gallery_socket(form, [], %{current_user: ctx.user, form_id: "project_form"})

      assert {:noreply, _socket} =
               Gallery.handle_event("select_image", %{"id" => to_string(ctx.image.id)}, socket)

      assert_receive {:phoenix, :send_update, {{Form, "project_form"}, assigns}}
      assert assigns.action == :put_gallery
      assert assigns.path == []
      assert assigns.key == :photos
      assert [%{image_id: image_id}] = assigns.gallery.gallery_objects
      assert image_id == ctx.image.id
    end

    test "a NESTED gallery addresses the entry form, not its own schema's", ctx do
      # The gallery is owned by a subrecord rendered inside a Page's form.
      # `Form.input/1` threads the entry form component's id down as `form_id`;
      # before the fix the component ignored it and derived one from its own
      # changeset's struct instead, naming a component that is not mounted.
      form = to_form(Changeset.change(%ProjectUpdate1{}), as: "page[projects][0]")

      socket =
        gallery_socket(form, [:projects, 0], %{current_user: ctx.user, form_id: "page_form"})

      assert {:noreply, _socket} =
               Gallery.handle_event("select_image", %{"id" => to_string(ctx.image.id)}, socket)

      assert_receive {:phoenix, :send_update, {{Form, "page_form"}, assigns}}
      assert assigns.path == [:projects, 0]
      assert assigns.key == :photos
    end

    test "falls back to the form name's root when no form_id was threaded", ctx do
      # A gallery rendered outside the standard field pipeline still has to land
      # somewhere real. The ROOT of a nested form name is the entry's own name —
      # never the owning schema's.
      form = to_form(Changeset.change(%ProjectUpdate1{}), as: "page[projects][0]")

      socket = gallery_socket(form, [:projects, 0], %{current_user: ctx.user})

      assert {:noreply, _socket} =
               Gallery.handle_event("select_image", %{"id" => to_string(ctx.image.id)}, socket)

      assert_receive {:phoenix, :send_update, {{Form, "page_form"}, _assigns}}
    end

    test "removing media reaches the same target", ctx do
      gallery = %Brando.Galleries.Gallery{
        id: 1,
        config_target: "gallery:Brando.MigrationTest.ProjectUpdate1:photos",
        gallery_objects: []
      }

      form = to_form(Changeset.change(%ProjectUpdate1{photos: gallery}), as: "page[projects][0]")

      socket =
        gallery_socket(form, [:projects, 0], %{
          current_user: ctx.user,
          form_id: "page_form",
          gallery_objects: [%GalleryObject{image_id: ctx.image.id}],
          selected_images: [ctx.image.id]
        })

      assert {:noreply, _socket} =
               Gallery.handle_event("select_image", %{"id" => to_string(ctx.image.id)}, socket)

      assert_receive {:phoenix, :send_update, {{Form, "page_form"}, assigns}}
      assert assigns.action == :put_gallery
      assert assigns.gallery.gallery_objects == []
    end
  end

  describe "D5 — merge_loaded_media/2" do
    test "keeps an object that already carries its loaded media" do
      loaded = %GalleryObject{image_id: 1, image: %Brando.Images.Image{id: 1, path: "a.jpg"}}

      assert [^loaded] = Galleries.merge_loaded_media([loaded], [])
    end

    test "borrows loaded media from the previous list by image id" do
      loaded = %GalleryObject{image_id: 1, image: %Brando.Images.Image{id: 1, path: "a.jpg"}}
      slim = %GalleryObject{image_id: 1}

      assert [%{image: %{path: "a.jpg"}}] = Galleries.merge_loaded_media([slim], [loaded])
    end

    test "borrows loaded media by video id too" do
      loaded = %GalleryObject{video_id: 9, video: %Brando.Videos.Video{id: 9}}
      slim = %GalleryObject{video_id: 9}

      assert [%{video: %Brando.Videos.Video{id: 9}}] =
               Galleries.merge_loaded_media([slim], [loaded])
    end

    test "does not borrow across different media" do
      loaded = %GalleryObject{image_id: 1, image: %Brando.Images.Image{id: 1}}
      slim = %GalleryObject{image_id: 2}

      assert [%{image_id: 2, image: %Ecto.Association.NotLoaded{}}] =
               Galleries.merge_loaded_media([slim], [loaded])
    end

    test "the changeset decides membership — a removed object does not linger" do
      loaded = %GalleryObject{image_id: 1, image: %Brando.Images.Image{id: 1}}

      assert Galleries.merge_loaded_media([], [loaded]) == []
    end
  end

  describe "D5 — the component tracks the changeset" do
    test "an externally added object shows up on the next update", ctx do
      empty = to_form(Changeset.change(%ProjectUpdate1{}))
      socket = gallery_socket(empty, [], %{current_user: ctx.user})

      # Something else (an upload delivery, a revision restore) writes the
      # gallery into the entry changeset. The component is only handed the new
      # field — with `assign_new` it kept showing the empty list forever.
      gallery = %Brando.Galleries.Gallery{
        id: 1,
        config_target: "gallery:Brando.MigrationTest.ProjectUpdate1:photos",
        gallery_objects: [
          %GalleryObject{image_id: ctx.image.id, image: ctx.image}
        ]
      }

      mutated = to_form(Changeset.change(%ProjectUpdate1{photos: gallery}))

      assert {:ok, socket} =
               Gallery.update(%{field: mutated[:photos], current_user: ctx.user, opts: []}, socket)

      assert [%{image_id: image_id}] = socket.assigns.gallery_objects
      assert image_id == ctx.image.id
      assert socket.assigns.selected_images == [ctx.image.id]
    end

    test "a slimmed object keeps the media the component had already loaded", ctx do
      # This is what makes re-deriving safe: writing the list back through
      # `put_assoc` strips the preloaded :image, so deriving alone would blank
      # every thumbnail.
      gallery = %Brando.Galleries.Gallery{
        id: 1,
        config_target: "gallery:Brando.MigrationTest.ProjectUpdate1:photos",
        gallery_objects: [%GalleryObject{image_id: ctx.image.id}]
      }

      form = to_form(Changeset.change(%ProjectUpdate1{photos: gallery}))

      socket =
        gallery_socket(form, [], %{
          current_user: ctx.user,
          gallery_objects: [%GalleryObject{image_id: ctx.image.id, image: ctx.image}]
        })

      assert {:ok, socket} =
               Gallery.update(%{field: form[:photos], current_user: ctx.user, opts: []}, socket)

      assert [%{image: %Brando.Images.Image{}}] = socket.assigns.gallery_objects
    end
  end
end
