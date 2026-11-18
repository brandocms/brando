defmodule BrandoAdmin.Components.Form.Input.GalleryBlockTest do
  # Gallery overrides point at an image or a video by `object_id`, and images
  # and videos are numbered by separate sequences. These tests put image N and
  # video N in the same gallery block and check that each keeps its own override
  # in the editor.
  use ExUnit.Case, async: true
  use Brando.ConnCase
  use Phoenix.Component

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.Content.Block, as: ContentBlock
  alias Brando.Factory
  alias Brando.Villain.Blocks.GalleryBlock, as: GalleryBlockData
  alias Brando.Villain.Blocks.GalleryObjectOverride
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.Input.Blocks.GalleryBlock
  alias BrandoAdmin.Components.Form.Input.Blocks.GalleryBlock.Object
  alias Ecto.Changeset
  alias Phoenix.Component

  setup do
    user = Factory.insert(:random_user)
    shared_id = 900_000 + System.unique_integer([:positive])
    image = Factory.insert(:image, id: shared_id, creator: user, title: "Image default")
    video = Factory.insert(:upload_video, id: shared_id, creator: user, title: "Video default")

    gallery = Factory.insert(:gallery)
    Factory.insert(:gallery_object, gallery_id: gallery.id, image_id: image.id, sequence: 0)
    Factory.insert(:gallery_object, gallery_id: gallery.id, video_id: video.id, sequence: 1)

    gallery = Brando.Repo.preload(gallery, [gallery_objects: [:image, video: [:thumbnail]]], force: true)

    overrides = [
      override(shared_id, :image, "Image caption"),
      override(shared_id, :video, "Video caption")
    ]

    {:ok, user: user, shared_id: shared_id, gallery: gallery, overrides: overrides}
  end

  defp override(id, type, title) do
    %GalleryObjectOverride{
      object_id: to_string(id),
      object_type: type,
      title: title,
      use_default_title: false
    }
  end

  defp media_key(%GalleryObjectOverride{object_type: type, object_id: id}), do: {type, id}

  describe "GalleryBlock.update/2" do
    defp update_gallery_block(gallery, overrides) do
      ref_form =
        %Brando.Content.Ref{uid: "galleryref", name: "gallery", gallery_id: gallery.id, gallery: gallery}
        |> Changeset.change()
        |> to_form(as: "ref")

      block_form =
        %GalleryBlockData{
          type: "gallery",
          data: %GalleryBlockData.Data{type: :gallery, gallery_object_overrides: overrides}
        }
        |> Changeset.change()
        |> to_form(as: "data")

      {:ok, socket} = GalleryBlock.mount(%Phoenix.LiveView.Socket{})
      update_gallery_block(socket, ref_form, block_form)
    end

    defp update_gallery_block(socket, ref_form, block_form) do
      {:ok, socket} =
        GalleryBlock.update(%{id: "gallery-block", block: block_form, ref_form: ref_form, form_id: "page_form"}, socket)

      socket
    end

    test "keeps a separate override for an image and a video with the same id", ctx do
      socket = update_gallery_block(ctx.gallery, ctx.overrides)
      id = to_string(ctx.shared_id)

      assert Enum.map(socket.assigns.initialized_overrides, &{media_key(&1), &1.title}) == [
               {{:image, id}, "Image caption"},
               {{:video, id}, "Video caption"}
             ]

      assert socket.assigns.override_data[{:image, id, nil}].current_title == "Image caption"
      assert socket.assigns.override_data[{:video, id, nil}].current_title == "Video caption"
    end

    test "gives an override stored without a type the type of its media", ctx do
      untyped = %{override(ctx.shared_id, :image, "Legacy caption") | object_type: nil}
      socket = update_gallery_block(ctx.gallery, [untyped])
      id = to_string(ctx.shared_id)

      assert Enum.map(socket.assigns.initialized_overrides, &{media_key(&1), &1.title}) == [
               {{:image, id}, "Legacy caption"},
               {{:video, id}, "Legacy caption"}
             ]
    end

    # Mirrors the nesting in `GalleryBlock.render/1`. Each object renders an
    # `OverrideForm` live component, and LiveView raises when two share an id.
    defp render_objects(assigns) do
      ~H"""
      <.inputs_for :let={block_data} field={@block[:data]}>
        <.inputs_for :let={gallery_form} field={@ref_form[:gallery]}>
          <.inputs_for :let={gallery_object_form} field={gallery_form[:gallery_objects]} skip_hidden>
            <Object.render
              gallery_object_form={gallery_object_form}
              gallery_objects={@gallery_objects}
              placements={@placements}
              display={@display}
              text_editor={assigns[:text_editor]}
              myself={@myself}
              uid={@uid}
              gallery_form={gallery_form}
              override_data={@override_data}
              block_data={block_data}
              form_id={@form_id}
            />
          </.inputs_for>
        </.inputs_for>
      </.inputs_for>
      """
    end

    test "renders one override form per object with its own caption", ctx do
      socket = update_gallery_block(ctx.gallery, ctx.overrides)

      html =
        render_component(
          &render_objects/1,
          Map.put(socket.assigns, :myself, %Phoenix.LiveComponent.CID{cid: 1})
        )

      [image_object, video_object] = ctx.gallery.gallery_objects
      assert html =~ ~s(id="gallery-object-galleryref-#{image_object.id}")
      assert html =~ ~s(id="gallery-object-galleryref-#{video_object.id}")
      assert html =~ "Image caption"
      assert html =~ "Video caption"
      assert length(Regex.scan(~r/name="[^"]*\[object_type\]"[^>]*value="image"/, html)) == 1
      assert length(Regex.scan(~r/name="[^"]*\[object_type\]"[^>]*value="video"/, html)) == 1
    end

    test "list display renders joined rows, grid renders the contact sheet", ctx do
      socket = update_gallery_block(ctx.gallery, ctx.overrides)
      assigns = Map.put(socket.assigns, :myself, %Phoenix.LiveComponent.CID{cid: 1})

      list_html = render_component(&render_objects/1, Map.put(assigns, :display, :list))

      assert list_html =~ ~s(class="gallery-block-list-title">Image caption<)
      assert list_html =~ ~s(class="gallery-block-list-title">Video caption<)
      assert list_html =~ "No alt text"
      refute list_html =~ "<figcaption"
      refute list_html =~ "media-type-badge"
      assert length(Regex.scan(~r/class="gallery-object-actions"/, list_html)) == 2

      grid_html = render_component(&render_objects/1, Map.put(assigns, :display, :grid))

      refute grid_html =~ "<figcaption"
      refute grid_html =~ "media-type-badge"
      refute grid_html =~ "No caption"
      assert length(Regex.scan(~r/class="gallery-tile"/, grid_html)) == 2
      refute grid_html =~ "gallery-block-list-row"
    end
  end

  describe "GalleryBlock grid" do
    defp block_socket_for(ctx) do
      ctx.gallery
      |> update_gallery_block(ctx.overrides)
      |> Phoenix.Component.assign(:target_ref, {Block, "block-galleryblk"})
      |> Phoenix.Component.assign(:ref_name, "gallery")
    end

    defp committed_overrides do
      assert_receive {:phoenix, :send_update, {{Block, "block-galleryblk"}, %{event: "update_ref_data", ref_data: data}}}
      Map.new(data.gallery_object_overrides, &{media_key(&1), &1})
    end

    test "squares show each object's caption and alt state, and the open popover", ctx do
      socket = block_socket_for(ctx)
      id = to_string(ctx.shared_id)

      assigns =
        socket.assigns
        |> Map.put(:myself, %Phoenix.LiveComponent.CID{cid: 1})
        |> Map.put(:display, :grid)
        |> Map.put(:text_editor, %{type: :image, id: id, placement: nil, kind: :alt})

      html = render_component(&render_objects/1, assigns)
      doc = Floki.parse_fragment!(html)

      assert doc |> Floki.find(".gallery-tile-number") |> Enum.map(&Floki.text/1) == ["1", "2"]
      # Both captions are overridden; only the image has alt text to miss.
      assert length(Floki.find(doc, ".gallery-tile-icon.is-set[aria-label=Caption]")) == 2
      assert [_] = Floki.find(doc, ".gallery-tile-icon.is-missing")
      assert [_] = Floki.find(doc, ".gallery-text-editor--alt")
      assert html =~ "Image caption"
      assert length(Floki.find(doc, "button.delete-x")) == 2
      assert [_] = Floki.find(doc, "button.edit-image-btn")
    end

    test "saving a caption writes the override the settings dialog edits", ctx do
      socket = block_socket_for(ctx)
      id = to_string(ctx.shared_id)

      {:noreply, socket} =
        GalleryBlock.handle_event(
          "save_object_text",
          %{"type" => "image", "id" => id, "kind" => "caption", "value" => "<p><em>Rich</em></p>"},
          socket
        )

      assert socket.assigns.text_editor == nil
      image = committed_overrides()[{:image, id}]
      assert image.title == "<p><em>Rich</em></p>"
      assert image.use_default_title == false

      # A video's caption is its own field, so its title keeps naming the player.
      GalleryBlock.handle_event(
        "save_object_text",
        %{"type" => "video", "id" => id, "kind" => "caption", "value" => "<p>Film</p>"},
        socket
      )

      video = committed_overrides()[{:video, id}]
      assert video.caption == "<p>Film</p>"
      assert video.use_default_caption == false
      assert video.title == "Video caption"
    end

    test "an empty alt text falls back to the library, a video has none", ctx do
      socket = block_socket_for(ctx)
      id = to_string(ctx.shared_id)

      GalleryBlock.handle_event(
        "save_object_text",
        %{"type" => "image", "id" => id, "kind" => "alt", "value" => " "},
        socket
      )

      image = committed_overrides()[{:image, id}]
      assert image.alt == nil
      assert image.use_default_alt == true

      assert {:noreply, _} =
               GalleryBlock.handle_event(
                 "save_object_text",
                 %{"type" => "video", "id" => id, "kind" => "alt", "value" => "x"},
                 socket
               )

      refute_receive {:phoenix, :send_update, _}
    end

    test "the view switch leaves the block's saved display alone", ctx do
      socket = block_socket_for(ctx)
      assert socket.assigns.view == :grid

      {:noreply, socket} = GalleryBlock.handle_event("set_gallery_view", %{"view" => "list"}, socket)

      assert socket.assigns.view == :list
      assert socket.assigns.display == :grid
      refute_receive {:phoenix, :send_update, _}
    end
  end

  # A gallery may hold one image twice (#3617): each placement is its own
  # object with its own override.
  describe "a repeated image" do
    setup ctx do
      gallery = Factory.insert(:gallery)
      image = Factory.insert(:image, creator: ctx.user, title: "Library caption")

      for sequence <- 0..1,
          do: Factory.insert(:gallery_object, gallery_id: gallery.id, image_id: image.id, sequence: sequence)

      gallery = Brando.Repo.preload(gallery, [gallery_objects: [:image, video: [:thumbnail]]], force: true)
      {:ok, repeated: gallery, repeated_image: image}
    end

    defp placed(image, placement, title) do
      %{override(image.id, :image, title) | placement: placement}
    end

    defp captions(socket) do
      Enum.map(socket.assigns.initialized_overrides, &{&1.placement, &1.title})
    end

    test "a caption stored for the image is copied into each placement", ctx do
      socket = update_gallery_block(ctx.repeated, [override(ctx.repeated_image.id, :image, "Shared")])

      assert captions(socket) == [{0, "Shared"}, {1, "Shared"}]
      id = to_string(ctx.repeated_image.id)
      assert socket.assigns.override_data[{:image, id, 0}].current_title == "Shared"
      assert socket.assigns.override_data[{:image, id, 1}].current_title == "Shared"
    end

    # The edit session names each override by its uid, so two editors'
    # changes meet on the same copy. Both editors give a gallery stored
    # without uids the same ones: each object's.
    test "an override stored without a uid takes its object's, and a copied one gets its own", ctx do
      [first, second] = ctx.repeated.gallery_objects
      stored = %{placed(ctx.repeated_image, 0, "First") | uid: "kept"}

      socket = update_gallery_block(ctx.repeated, [stored, placed(ctx.repeated_image, 1, "Second")])
      assert Enum.map(socket.assigns.initialized_overrides, & &1.uid) == ["kept", "g#{second.id}"]

      socket = update_gallery_block(ctx.repeated, [%{override(ctx.repeated_image.id, :image, "Shared") | uid: "shared"}])
      assert Enum.map(socket.assigns.initialized_overrides, & &1.uid) == ["shared", "g#{second.id}"]

      socket = update_gallery_block(ctx.repeated, [])
      assert Enum.map(socket.assigns.initialized_overrides, & &1.uid) == ["g#{first.id}", "g#{second.id}"]
    end

    # An override keeps its uid when its media is replaced, so another
    # override may already hold the uid an object would give. One whose uid
    # names another of the gallery's objects gets its own: at save, an
    # override takes the placement of the object its uid names
    # (`GalleryObjectOverride.settle/1`).
    test "an override given a uid gets one no other override holds", ctx do
      [first, second] = ctx.repeated.gallery_objects
      elsewhere = %{placed(ctx.repeated_image, 1, "Second") | uid: "g#{first.id}"}

      socket = update_gallery_block(ctx.repeated, [placed(ctx.repeated_image, 0, "First"), elsewhere])

      assert Enum.map(socket.assigns.initialized_overrides, &{&1.uid, &1.placement}) == [
               {"g#{first.id}", 0},
               {"g#{second.id}", 1}
             ]

      assert GalleryObjectOverride.unique_uid(%{image_id: 5}, MapSet.new(["image-5", "image-5-2"])) == "image-5-3"
    end

    # A reorder renumbers the placements and leaves the list as it was. The
    # edit session sends a change to an override by its uid only while the
    # list keeps its order: the overrides the gallery sends stay in the
    # block's order, not the objects'.
    test "the overrides keep the block's order after the copies were reordered", ctx do
      stored = [
        %{placed(ctx.repeated_image, 1, "Second") | uid: "a"},
        %{placed(ctx.repeated_image, 0, "First") | uid: "b"}
      ]

      socket = update_gallery_block(ctx.repeated, stored)

      assert Enum.map(socket.assigns.initialized_overrides, &{&1.uid, &1.placement, &1.title}) == [
               {"a", 1, "Second"},
               {"b", 0, "First"}
             ]
    end

    test "each placement keeps its own caption", ctx do
      overrides = [placed(ctx.repeated_image, 1, "Second"), placed(ctx.repeated_image, 0, "First")]
      socket = update_gallery_block(ctx.repeated, overrides)

      assert Enum.sort(captions(socket)) == [{0, "First"}, {1, "Second"}]

      html =
        render_component(
          &render_objects/1,
          socket.assigns |> Map.put(:myself, %Phoenix.LiveComponent.CID{cid: 1}) |> Map.put(:display, :list)
        )

      assert html |> Floki.parse_fragment!() |> Floki.find(".gallery-block-list-title") |> Enum.map(&Floki.text/1) ==
               ["First", "Second"]

      # One override form per object, each with its own placement
      assert Regex.scan(~r/name="[^"]*\[placement\]"[^>]*value="(\d)"/, html, capture: :all_but_first) == [["0"], ["1"]]
    end

    # Another editor reorders the repeats while this one has a caption open: the
    # open caption stays with its gallery object.
    test "an open caption follows its object when the placements are reordered", ctx do
      overrides = [placed(ctx.repeated_image, 0, "First"), placed(ctx.repeated_image, 1, "Second")]

      socket =
        ctx.repeated
        |> update_gallery_block(overrides)
        |> Phoenix.Component.assign(:target_ref, {Block, "block-galleryblk"})
        |> Phoenix.Component.assign(:ref_name, "gallery")

      id = to_string(ctx.repeated_image.id)

      {:noreply, socket} =
        GalleryBlock.handle_event(
          "open_text_editor",
          %{"type" => "image", "id" => id, "placement" => 1, "kind" => "caption"},
          socket
        )

      # The second object is now first, and its caption with it
      [first, second] = ctx.repeated.gallery_objects
      reordered = %{ctx.repeated | gallery_objects: [second, first]}

      ref_form =
        %Brando.Content.Ref{uid: "galleryref", name: "gallery", gallery_id: reordered.id, gallery: reordered}
        |> Changeset.change()
        |> to_form(as: "ref")

      block_form =
        %GalleryBlockData{
          type: "gallery",
          data: %GalleryBlockData.Data{
            type: :gallery,
            gallery_object_overrides: [placed(ctx.repeated_image, 0, "Second"), placed(ctx.repeated_image, 1, "First")]
          }
        }
        |> Changeset.change()
        |> to_form(as: "data")

      socket = update_gallery_block(socket, ref_form, block_form)
      assert %{placement: 0} = socket.assigns.text_editor

      # A save sent before the browser saw the reorder still names placement 1
      GalleryBlock.handle_event(
        "save_object_text",
        %{"type" => "image", "id" => id, "placement" => 1, "kind" => "caption", "value" => "<p>Edited</p>"},
        socket
      )

      assert_receive {:phoenix, :send_update, {{Block, "block-galleryblk"}, %{event: "update_ref_data", ref_data: data}}}
      assert Enum.map(data.gallery_object_overrides, &{&1.placement, &1.title}) == [{0, "<p>Edited</p>"}, {1, "First"}]
    end

    test "a caption saved for one placement leaves the other alone", ctx do
      socket =
        ctx.repeated
        |> update_gallery_block([placed(ctx.repeated_image, 0, "First"), placed(ctx.repeated_image, 1, "Second")])
        |> Phoenix.Component.assign(:target_ref, {Block, "block-galleryblk"})
        |> Phoenix.Component.assign(:ref_name, "gallery")

      id = to_string(ctx.repeated_image.id)

      {:noreply, socket} =
        GalleryBlock.handle_event(
          "open_text_editor",
          %{"type" => "image", "id" => id, "placement" => 1, "kind" => "caption"},
          socket
        )

      assert %{type: :image, id: ^id, placement: 1, kind: :caption} = socket.assigns.text_editor

      GalleryBlock.handle_event(
        "save_object_text",
        %{"type" => "image", "id" => id, "placement" => 1, "kind" => "caption", "value" => "<p>Edited</p>"},
        socket
      )

      assert_receive {:phoenix, :send_update, {{Block, "block-galleryblk"}, %{event: "update_ref_data", ref_data: data}}}

      assert Enum.map(data.gallery_object_overrides, &{&1.placement, &1.title}) == [
               {0, "First"},
               {1, "<p>Edited</p>"}
             ]
    end
  end

  describe "Block ref data commits" do
    setup ctx do
      params = %{
        "uid" => "galleryblk1",
        "type" => "module",
        "source" => "Elixir.Brando.Pages.Page.Blocks",
        "creator_id" => ctx.user.id,
        "refs" => [
          %{
            "uid" => "galleryref1",
            "name" => "gallery",
            "gallery_id" => ctx.gallery.id,
            "data" => %{
              "type" => "gallery",
              "data" => %{
                "gallery_object_overrides" =>
                  Enum.map(ctx.overrides, fn override ->
                    %{
                      "object_id" => override.object_id,
                      "object_type" => to_string(override.object_type),
                      "title" => override.title,
                      "use_default_title" => false
                    }
                  end)
              }
            }
          }
        ]
      }

      block = %ContentBlock{} |> ContentBlock.recursive_block_changeset(params, ctx.user) |> Brando.Repo.insert!()
      page = Factory.insert(:page, creator: ctx.user)

      entry_block =
        %Brando.Pages.Page.Blocks{entry_id: page.id, block_id: block.id, sequence: 0}
        |> Brando.Repo.insert!()
        |> Brando.Repo.preload([
          :entry,
          block: [:vars, :table_rows, :block_identifiers, :children, refs: Brando.Content.Ref.preloads()]
        ])

      {:ok, entry_block: entry_block}
    end

    defp block_socket(entry_block, user) do
      form = to_form(Changeset.change(entry_block), as: "entry_block", id: "entry_block_form-galleryblk1")

      %Phoenix.LiveView.Socket{}
      |> Component.assign(:form, form)
      |> Component.assign(:uid, "galleryblk1")
      |> Component.assign(:block_module, Brando.Pages.Page.Blocks)
      |> Component.assign(:current_user_id, user.id)
      |> Component.assign(:entry, entry_block.entry)
      |> Component.assign(:has_vars?, false)
      |> Component.assign(:has_children?, false)
      |> Component.assign(:has_table_rows?, false)
      |> Component.assign(:live_preview_active?, false)
      |> Component.assign(:original_block_identifiers, [])
      |> Component.assign(:form_id, "page_form")
      |> Component.assign(:block_field, "blocks")
      |> Component.assign(:belongs_to, :root)
    end

    defp resulting_overrides(socket) do
      [ref] =
        socket.assigns.form.source
        |> Changeset.apply_changes()
        |> Map.fetch!(:block)
        |> Map.fetch!(:refs)

      # The commit leaves the ref's polymorphic `data` as a changeset.
      data =
        case ref.data do
          %Changeset{} = changeset -> Changeset.apply_changes(changeset)
          data -> data
        end

      Enum.map(data.data.gallery_object_overrides, &{media_key(&1), &1.title})
    end

    test "removing the video keeps the image's override", ctx do
      socket = block_socket(ctx.entry_block, ctx.user)

      {:ok, socket} =
        Block.update(%{event: "update_ref_data", ref_name: "gallery", remove_gallery_video_id: ctx.shared_id}, socket)

      assert resulting_overrides(socket) == [{{:image, to_string(ctx.shared_id)}, "Image caption"}]
    end

    test "adding a video next to an image with the same id gives it its own override", ctx do
      entry_block = drop_video_override(ctx.entry_block)
      socket = block_socket(entry_block, ctx.user)
      id = to_string(ctx.shared_id)

      {:ok, socket} =
        Block.update(%{event: "update_ref_data", ref_name: "gallery", add_gallery_video_id: ctx.shared_id}, socket)

      assert resulting_overrides(socket) == [{{:image, id}, "Image caption"}, {{:video, id}, nil}]
    end

    test "adding an image the gallery already holds leaves the gallery as it was", ctx do
      socket = block_socket(ctx.entry_block, ctx.user)
      before = resulting_media(socket)
      assert {:image, ctx.shared_id} in before

      {:ok, socket} =
        Block.update(%{event: "update_ref_data", ref_name: "gallery", add_gallery_image_id: ctx.shared_id}, socket)

      assert resulting_media(socket) == before
    end

    defp resulting_media(socket) do
      [ref] =
        socket.assigns.form.source
        |> Changeset.apply_changes()
        |> Map.fetch!(:block)
        |> Map.fetch!(:refs)

      Enum.map(ref.gallery.gallery_objects, fn
        %{image_id: id} when not is_nil(id) -> {:image, id}
        %{video_id: id} -> {:video, id}
      end)
    end

    defp drop_video_override(entry_block) do
      [ref] = entry_block.block.refs
      overrides = Enum.reject(ref.data.data.gallery_object_overrides, &(&1.object_type == :video))
      ref = put_in(ref.data.data.gallery_object_overrides, overrides)
      put_in(entry_block.block.refs, [ref])
    end
  end

  # "Edit image" → "Save as new copy" on one placement of a repeated image:
  # the copy takes that placement's place, with its caption; the other
  # placement keeps the original image and its own caption.
  describe "save as new copy on a repeated image" do
    setup ctx do
      image = Factory.insert(:image, creator: ctx.user, title: "Library caption")
      copy = Factory.insert(:image, creator: ctx.user)
      gallery = Factory.insert(:gallery)

      objects =
        for sequence <- 0..1,
            do: Factory.insert(:gallery_object, gallery_id: gallery.id, image_id: image.id, sequence: sequence)

      overrides =
        for {placement, title} <- [{0, "First"}, {1, "Second"}] do
          %{
            "object_id" => to_string(image.id),
            "object_type" => "image",
            "placement" => placement,
            "title" => title,
            "use_default_title" => false
          }
        end

      params = %{
        "uid" => "galleryblk1",
        "type" => "module",
        "source" => "Elixir.Brando.Pages.Page.Blocks",
        "creator_id" => ctx.user.id,
        "refs" => [
          %{
            "uid" => "galleryref1",
            "name" => "gallery",
            "gallery_id" => gallery.id,
            "data" => %{"type" => "gallery", "data" => %{"gallery_object_overrides" => overrides}}
          }
        ]
      }

      block = %ContentBlock{} |> ContentBlock.recursive_block_changeset(params, ctx.user) |> Brando.Repo.insert!()
      page = Factory.insert(:page, creator: ctx.user)

      entry_block =
        %Brando.Pages.Page.Blocks{entry_id: page.id, block_id: block.id, sequence: 0}
        |> Brando.Repo.insert!()
        |> Brando.Repo.preload([
          :entry,
          block: [:vars, :table_rows, :block_identifiers, :children, refs: Brando.Content.Ref.preloads()]
        ])

      gallery = Brando.Repo.preload(gallery, [gallery_objects: [:image, video: [:thumbnail]]], force: true)

      {:ok,
       repeated_block: entry_block, repeated: gallery, repeated_image: image, copy: copy, repeated_objects: objects}
    end

    defp placed_titles(socket) do
      [ref] =
        socket.assigns.form.source
        |> Changeset.apply_changes()
        |> Map.fetch!(:block)
        |> Map.fetch!(:refs)

      data =
        case ref.data do
          %Changeset{} = changeset -> Changeset.apply_changes(changeset)
          data -> data
        end

      data.data.gallery_object_overrides
      |> Enum.map(&{&1.object_id, &1.placement, &1.title})
      |> Enum.sort()
    end

    test "the copy replaces the edited placement only, which keeps its caption", ctx do
      socket = block_socket(ctx.repeated_block, ctx.user)
      [_first, second] = ctx.repeated_objects
      image_id = ctx.repeated_image.id
      target = %{gallery_object_id: second.id, placement: {:image, to_string(image_id), 1}}

      {:ok, socket} =
        Block.update(
          %{event: "update_ref_data", ref_name: "gallery", replace_gallery_image: {image_id, ctx.copy, target}},
          socket
        )

      assert resulting_media(socket) == [{:image, image_id}, {:image, ctx.copy.id}]

      # The image is now held once, so neither override needs a placement
      assert placed_titles(socket) ==
               Enum.sort([{to_string(image_id), nil, "First"}, {to_string(ctx.copy.id), nil, "Second"}])
    end

    test "an object not saved yet is found by its placement", ctx do
      socket = block_socket(ctx.repeated_block, ctx.user)
      image_id = ctx.repeated_image.id
      target = %{gallery_object_id: nil, placement: {:image, to_string(image_id), 0}}

      {:ok, socket} =
        Block.update(
          %{event: "update_ref_data", ref_name: "gallery", replace_gallery_image: {image_id, ctx.copy, target}},
          socket
        )

      assert resulting_media(socket) == [{:image, ctx.copy.id}, {:image, image_id}]

      assert placed_titles(socket) ==
               Enum.sort([{to_string(ctx.copy.id), nil, "First"}, {to_string(image_id), nil, "Second"}])
    end

    test "the editor opens for the placement it was opened from, and the copy goes back to it", ctx do
      socket =
        ctx.repeated
        |> update_gallery_block([placed(ctx.repeated_image, 0, "First"), placed(ctx.repeated_image, 1, "Second")])
        |> Phoenix.Component.assign(:target_ref, {Block, "block-galleryblk"})
        |> Phoenix.Component.assign(:ref_name, "gallery")

      [first, second] = ctx.repeated.gallery_objects
      image_id = ctx.repeated_image.id

      {:noreply, socket} =
        GalleryBlock.handle_event("open_image_editor", %{"image_id" => to_string(image_id), "index" => 1}, socket)

      assert_receive {:phoenix, :send_update, {{BrandoAdmin.Components.Form, "page_form"}, assigns}}
      assert assigns.action == :set_edit_image_from_block
      assert assigns.old_image_id == image_id
      target = assigns.gallery_object
      assert target == %{gallery_object_id: second.id, placement: {:image, to_string(image_id), 1}}

      {:ok, socket} =
        GalleryBlock.update(
          %{event: "image_editor_new_copy", new_image: ctx.copy, old_image_id: image_id, gallery_object: target},
          socket
        )

      assert Enum.map(socket.assigns.gallery_objects, &{&1.id, &1.image_id}) == [
               {first.id, image_id},
               {second.id, ctx.copy.id}
             ]

      assert_receive {:phoenix, :send_update, {{Block, "block-galleryblk"}, %{event: "update_ref_data"} = commit}}
      assert commit.replace_gallery_image == {image_id, ctx.copy, target}
    end

    # The editor closes as the copy starts uploading; the copy goes back to
    # the object the editor was opened from.
    test "the form hands the copy back with the object it was made for", ctx do
      [_first, second] = ctx.repeated_objects
      target = %{gallery_object_id: second.id, placement: {:image, to_string(ctx.repeated_image.id), 1}}

      {:ok, socket} =
        BrandoAdmin.Components.Form.update(
          %{
            action: :set_edit_image_from_block,
            image: ctx.repeated_image,
            block_target: {GalleryBlock, "gallery-block"},
            old_image_id: ctx.repeated_image.id,
            gallery_object: target
          },
          Component.assign(%Phoenix.LiveView.Socket{}, :current_user, ctx.user)
        )

      assert {:noreply, socket} =
               BrandoAdmin.Components.Form.handle_event(
                 "image_editor_save",
                 %{"mode" => "new_copy", "focal_x" => 50, "focal_y" => 50},
                 socket
               )

      assert {:noreply, _socket} =
               Oban.Testing.with_testing_mode(:manual, fn ->
                 BrandoAdmin.Components.Form.refocus_image_editor_copy(socket, ctx.copy)
               end)

      assert_receive {:phoenix, :send_update, {{GalleryBlock, "gallery-block"}, %{event: "image_editor_new_copy"} = assigns}}
      assert assigns.old_image_id == ctx.repeated_image.id
      assert assigns.gallery_object == target
    end
  end
end
