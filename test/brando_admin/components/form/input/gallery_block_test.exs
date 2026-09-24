defmodule BrandoAdmin.Components.Form.Input.GalleryBlockTest do
  # Gallery overrides point at an image or a video by `object_id`, and images
  # and videos are numbered by separate sequences. These tests put image N and
  # video N in the same gallery block and check that each keeps its own override
  # in the editor.
  use ExUnit.Case, async: false
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

      assert socket.assigns.override_data[{:image, id}].current_title == "Image caption"
      assert socket.assigns.override_data[{:video, id}].current_title == "Video caption"
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
              display={@display}
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

      id = ctx.shared_id
      assert html =~ ~s(id="gallery-object-galleryref-image-#{id}")
      assert html =~ ~s(id="gallery-object-galleryref-video-#{id}")
      assert html =~ "Image caption"
      assert html =~ "Video caption"
      assert length(Regex.scan(~r/name="[^"]*\[object_type\]"[^>]*value="image"/, html)) == 1
      assert length(Regex.scan(~r/name="[^"]*\[object_type\]"[^>]*value="video"/, html)) == 1
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
end
