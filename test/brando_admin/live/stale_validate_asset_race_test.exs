defmodule BrandoAdmin.StaleValidateAssetRaceTest do
  @moduledoc """
  An asset delivered by the UploadManager lives only in the form's changeset
  `changes` until the browser has applied the delivery render. A `validate` or
  `save` the browser serialized before that render (a debounced textarea, a
  rich-text commit) still carries the pre-delivery value for the asset, and
  casting those params onto `socket.assigns.entry` — which never receives the
  unsaved asset — used to drop it silently.

  Asset ids and galleries the form process has written are therefore owned by
  the server: params never supply them again until the form is rebuilt from a
  stored entry.
  """
  use Brando.LiveCase

  import Phoenix.Component, only: [to_form: 1, to_form: 2]

  alias Brando.MigrationTest.ProjectUpdate1
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input.Gallery
  alias Ecto.Changeset
  alias Phoenix.Component

  @form "#page_form_form"
  @media "#page_meta_image-media"

  describe "single-asset entry field" do
    setup %{current_user: user} do
      {:ok, page: Factory.insert(:page, creator: user), image: processed_image(user)}
    end

    test "a validate serialized before delivery keeps the delivered image", %{
      conn: conn,
      page: page,
      image: image
    } do
      {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
      html = type(view, "title", "Edited")

      # What the browser serializes while the upload is in flight.
      stale = form_params(html, @form)
      assert stale["page"]["meta_image_id"] == ""

      deliver(view, "meta_image", image)
      delivered = await_selector(view, "#{@media} img")
      assert hidden_meta_image_id(delivered) == to_string(image.id)

      # The debounced meta description fires with the params it read before the
      # delivery render reached the DOM.
      after_validate = stale_change(view, stale, "meta_description", "Typed before the upload finished")

      assert hidden_meta_image_id(after_validate) == to_string(image.id)
      assert has_element?(view, "#{@media} img")
    end

    test "delivery re-renders the field on a form that was never validated", %{
      conn: conn,
      page: page,
      image: image
    } do
      {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")

      deliver(view, "meta_image", image)

      delivered = await_selector(view, "#{@media} img")
      assert hidden_meta_image_id(delivered) == to_string(image.id)
    end

    test "a validate serialized before a removal does not bring the image back", %{
      conn: conn,
      current_user: user,
      image: image
    } do
      page = Factory.insert(:page, creator: user, meta_image_id: image.id)
      {view, html} = live_form(conn, "/admin/pages/update/#{page.id}")

      stale = form_params(html, @form)
      assert stale["page"]["meta_image_id"] == to_string(image.id)

      # What the field's remove button sends (`Input.Image` "remove_image").
      Phoenix.LiveView.send_update(view.pid, Form,
        id: "page_form",
        event: "clear_entry_field_asset",
        field: :meta_image,
        path: []
      )

      removed = render(view)
      assert hidden_meta_image_id(removed) == ""

      after_validate = stale_change(view, stale, "meta_description", "Typed before the removal landed")

      assert hidden_meta_image_id(after_validate) == ""
      refute has_element?(view, "#{@media} img")
    end
  end

  describe "saving" do
    setup %{current_user: user} do
      {:ok, image: processed_image(user)}
    end

    test "a save serialized before delivery still stores the delivered image", %{conn: conn, image: image} do
      user = Factory.insert(:random_user, avatar: nil)
      form = "#user_form_form"
      {view, html} = live_form(conn, "/admin/users/update/#{user.id}", "user_form")

      stale = form_params(html, form)
      assert stale["user"]["avatar_id"] == ""

      deliver(view, "avatar", image)
      await_selector(view, ~s(#{form} input[name="user[avatar_id]"][value="#{image.id}"]))

      view |> element(form) |> render_submit(stale)

      assert Brando.Repo.get!(Brando.Users.User, user.id).avatar_id == image.id
    end
  end

  describe "gallery entry field" do
    setup %{current_user: user} do
      {:ok, user: user, first: processed_image(user), second: processed_image(user)}
    end

    test "a validate serialized between two deliveries keeps both objects", ctx do
      socket = gallery_form_socket(ctx.user)

      {:ok, socket} = Form.update(gallery_delivery(ctx.first), socket)
      assert gallery_image_ids(socket) == ids([ctx.first])

      # The browser rendered the first object's hidden inputs and serialized
      # the form before the second delivery's render arrived.
      stale = gallery_params(ctx.first, "Typed before the second upload finished")

      {:ok, socket} = Form.update(gallery_delivery(ctx.second), socket)
      assert gallery_image_ids(socket) == ids([ctx.first, ctx.second])

      {:noreply, socket} = Form.handle_event("validate", stale, socket)

      assert gallery_image_ids(socket) == ids([ctx.first, ctx.second])
    end

    test "a validate serialized before the first delivery keeps the gallery", ctx do
      socket = gallery_form_socket(ctx.user)

      # Empty gallery: its inputs are not rendered, so the form carries no key.
      stale = %{"project" => %{"title" => "Typed before the upload finished"}, "_target" => ["project", "title"]}

      {:ok, socket} = Form.update(gallery_delivery(ctx.first), socket)
      assert gallery_image_ids(socket) == ids([ctx.first])

      {:noreply, socket} = Form.handle_event("validate", stale, socket)

      assert gallery_image_ids(socket) == ids([ctx.first])
    end

    test "a reordered gallery keeps its order through a stale validate", ctx do
      socket = gallery_form_socket(ctx.user)
      {:ok, socket} = Form.update(gallery_delivery(ctx.first), socket)
      {:ok, socket} = Form.update(gallery_delivery(ctx.second), socket)

      stale = gallery_params(ctx.first, "Typed before the reorder landed")

      reordered = socket.assigns.form.source |> Changeset.get_field(:photos) |> reorder([1, 0])
      {:ok, socket} = Form.update(%{action: :put_gallery, path: [], key: :photos, gallery: reordered}, socket)
      assert gallery_image_ids(socket) == ids([ctx.second, ctx.first])

      {:noreply, socket} = Form.handle_event("validate", stale, socket)

      assert gallery_image_ids(socket) == ids([ctx.second, ctx.first])
    end

    test "the gallery input commits a drag reorder to the entry form", ctx do
      gallery = %Brando.Galleries.Gallery{
        config_target: "gallery:Brando.MigrationTest.ProjectUpdate1:photos",
        gallery_objects: [
          %Brando.Galleries.GalleryObject{image_id: ctx.first.id, image: ctx.first, sequence: 0},
          %Brando.Galleries.GalleryObject{image_id: ctx.second.id, image: ctx.second, sequence: 1}
        ]
      }

      form = to_form(Changeset.change(%ProjectUpdate1{photos: gallery}))

      socket =
        %Phoenix.LiveView.Socket{}
        |> Component.assign(:field, form[:photos])
        |> Component.assign(:path, [])
        |> Component.assign(:form_id, "project_form")
        |> Component.assign(:gallery_objects, gallery.gallery_objects)

      assert {:noreply, socket} = Gallery.handle_event("reposition", %{"order" => ["1", "0"]}, socket)
      assert Enum.map(socket.assigns.gallery_objects, & &1.image_id) == [ctx.second.id, ctx.first.id]

      assert_receive {:phoenix, :send_update, {{Form, "project_form"}, assigns}}
      assert assigns.action == :put_gallery
      assert assigns.key == :photos

      assert Enum.map(assigns.gallery.gallery_objects, &{&1.image_id, &1.sequence}) ==
               [{ctx.second.id, 0}, {ctx.first.id, 1}]
    end

    test "removing an object from an uploaded gallery removes it, through a stale validate too", ctx do
      socket = gallery_form_socket(ctx.user)
      {:ok, socket} = Form.update(gallery_delivery(ctx.first), socket)
      {:ok, socket} = Form.update(gallery_delivery(ctx.second), socket)

      # Serialized while both objects were still rendered.
      stale = gallery_params([ctx.first, ctx.second], "Typed before the removal landed")

      gallery_socket = gallery_input_socket(socket.assigns.form[:photos])

      assert {:noreply, gallery_socket} =
               Gallery.handle_event("remove_object", %{"type" => "image", "id" => ctx.first.id}, gallery_socket)

      assert Enum.map(gallery_socket.assigns.gallery_objects, & &1.image_id) == [ctx.second.id]

      assert_receive {:phoenix, :send_update, {{Form, "project_form"}, %{action: :put_gallery} = put_gallery}}
      {:ok, socket} = Form.update(put_gallery, socket)
      assert gallery_image_ids(socket) == ids([ctx.second])

      {:noreply, socket} = Form.handle_event("validate", stale, socket)

      assert gallery_image_ids(socket) == ids([ctx.second])
    end

    test "the gallery input ignores removal of media it does not hold", ctx do
      socket = gallery_form_socket(ctx.user)
      {:ok, socket} = Form.update(gallery_delivery(ctx.first), socket)
      gallery_socket = gallery_input_socket(socket.assigns.form[:photos])

      for params <- [
            %{"type" => "image", "id" => ctx.second.id},
            %{"type" => "video", "id" => ctx.first.id},
            %{"type" => "image", "id" => "x"}
          ] do
        assert {:noreply, ^gallery_socket} = Gallery.handle_event("remove_object", params, gallery_socket)
      end

      refute_receive {:phoenix, :send_update, {{Form, _}, _}}
    end

    test "the grid thumbnail removes through the server event, not the drop param", ctx do
      object = %Brando.Galleries.GalleryObject{image_id: ctx.first.id, image: ctx.first}

      html =
        render_component(&Gallery.gallery_object/1, %{
          id: "project_photos",
          gallery_objects: [object],
          gallery_object_field: gallery_object_field(object),
          parent_form_name: "project[photos]",
          preview_layout: :grid,
          myself: %Phoenix.LiveComponent.CID{cid: 1}
        })

      [button] = html |> Floki.parse_fragment!() |> Floki.find("button.delete-object")
      assert Floki.attribute(button, "name") == []
      assert [click] = Floki.attribute(button, "phx-click")
      assert click =~ "remove_object"
      assert click =~ ~s("id":#{ctx.first.id})

      # The Gallery blueprint's own editor has no owner above it and still
      # removes through the drop param.
      html =
        render_component(&Gallery.Thumb.thumb/1, %{
          gallery_objects: [object],
          gallery_object_field: gallery_object_field(object),
          form_name: "gallery[gallery_objects][0]"
        })

      [button] = html |> Floki.parse_fragment!() |> Floki.find("button.delete-object")
      assert Floki.attribute(button, "name") == ["gallery[gallery_objects][0][drop_gallery_object_ids][]"]
    end

    test "the gallery input ignores an order that is not a permutation of its objects", ctx do
      form = to_form(Changeset.change(%ProjectUpdate1{photos: nil}))

      socket =
        %Phoenix.LiveView.Socket{}
        |> Component.assign(:field, form[:photos])
        |> Component.assign(:path, [])
        |> Component.assign(:form_id, "project_form")
        |> Component.assign(:gallery_objects, [%{image_id: ctx.first.id}, %{image_id: ctx.second.id}])

      for order <- [["0", "1"], ["1", "1"], ["2", "0"], ["x", "0"], ["0"]] do
        assert {:noreply, _} = Gallery.handle_event("reposition", %{"order" => order}, socket)
      end

      refute_receive {:phoenix, :send_update, _}
    end
  end

  defp processed_image(user),
    do: Factory.insert(:image, creator: user, focal: %Brando.Images.Focal{x: 50, y: 50}, status: :processed)

  defp deliver(view, field, asset),
    do: send(view.pid, {:asset_ready, %{"kind" => "entry_field", "field" => field}, asset})

  defp type(view, field, value) do
    view |> element(@form) |> render_change(%{"_target" => ["page", field], "page" => %{field => value}})
  end

  defp stale_change(view, stale, field, value) do
    params =
      stale
      |> put_in(["page", field], value)
      |> Map.put("_target", ["page", field])

    view |> element(@form) |> render_change(params)
  end

  defp hidden_meta_image_id(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find(~s(#{@form} input[name="page[meta_image_id]"]))
    |> Floki.attribute("value")
    |> List.first()
  end

  defp gallery_delivery(image) do
    %{event: "entry_field_upload_complete", asset_type: :gallery, field: :photos, path: [], asset: image}
  end

  # The params the gallery input renders for objects already in the DOM.
  defp gallery_params(images, title) do
    objects =
      images
      |> List.wrap()
      |> Enum.with_index()
      |> Map.new(fn {image, index} ->
        {to_string(index), %{"image_id" => to_string(image.id), "video_id" => "", "gallery_id" => ""}}
      end)

    %{
      "project" => %{
        "title" => title,
        "photos" => %{
          "config_target" => "gallery:Brando.MigrationTest.ProjectUpdate1:photos",
          "gallery_objects" => objects,
          "sort_gallery_object_ids" => objects |> Map.keys() |> Enum.sort()
        }
      },
      "_target" => ["project", "title"]
    }
  end

  defp gallery_input_socket(field) do
    gallery_objects = Changeset.get_field(field.form.source, field.field).gallery_objects

    %Phoenix.LiveView.Socket{}
    |> Component.assign(:field, field)
    |> Component.assign(:path, [])
    |> Component.assign(:form_id, "project_form")
    |> Component.assign(:gallery_objects, gallery_objects)
    |> Component.assign(:selected_images, Enum.map(gallery_objects, & &1.image_id))
    |> Component.assign(:selected_videos, [])
  end

  defp gallery_object_field(object) do
    form = to_form(Changeset.change(object), as: "project[photos][gallery_objects][0]")
    %{form | index: 0}
  end

  defp reorder(gallery, indices) do
    objects = Enum.map(indices, &Enum.at(gallery.gallery_objects, &1))

    %{
      config_target: gallery.config_target,
      gallery_objects: BrandoAdmin.Components.Form.Input.Gallery.Media.slim(objects)
    }
  end

  # Strings, so a failure prints ids rather than charlists.
  defp ids(images), do: Enum.map(images, &to_string(&1.id))

  defp gallery_image_ids(socket) do
    case Changeset.get_field(socket.assigns.form.source, :photos) do
      nil -> []
      gallery -> Enum.map(gallery.gallery_objects, &to_string(&1.image_id))
    end
  end

  defp gallery_form_socket(user) do
    entry = %ProjectUpdate1{photos: nil}

    %Phoenix.LiveView.Socket{}
    |> Component.assign(:form, to_form(Changeset.change(entry)))
    |> Component.assign(:entry, entry)
    |> Component.assign(:schema, ProjectUpdate1)
    |> Component.assign(:singular, "project")
    |> Component.assign(:current_user, user)
    |> Component.assign(:processing_images, [])
    |> Component.assign(:dirty_fields, [])
    |> Component.assign(:has_blocks?, false)
    |> Component.assign(:live_preview_active?, false)
  end
end
