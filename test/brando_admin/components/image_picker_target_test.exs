defmodule BrandoAdmin.Components.ImagePickerTargetTest do
  # A block's upload opened the picker scoped to whatever field opened it
  # last: without a `config_target` of its own it kept the previous one, so
  # after a page's meta image the block browsed `images/meta`.
  use Brando.ConnCase, async: false

  alias BrandoAdmin.Components.ImagePicker

  defp picker do
    # `stream/3` in mount needs a LiveView lifecycle on the socket.
    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, flash: %{}},
      private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}, live_temp: %{}}
    }

    {:ok, socket} = ImagePicker.mount(socket)
    socket
  end

  test "a block upload without a target of its own browses the default target" do
    {:ok, socket} =
      ImagePicker.update(
        %{config_target: "image:Brando.Pages.Page:meta_image", event_target: nil, multi: false, selected_images: []},
        picker()
      )

    {:ok, socket} = ImagePicker.update(%{event: "open_block_upload_browser", upload_name: "u"}, socket)

    assert socket.assigns.config_target == "default"
  end

  # `upload_in_form?` comes from where the form renders the picker, before any
  # opening; `params` are what a field sends to open it.
  defp open_select(params, in_form? \\ false) do
    socket = picker()
    socket = %{socket | assigns: Map.merge(socket.assigns, %{id: "image-picker", upload_in_form?: in_form?})}

    {:ok, socket} =
      ImagePicker.update(
        Map.merge(%{config_target: "default", event_target: nil, multi: true, selected_images: []}, params),
        socket
      )

    socket
  end

  test "picking inside a form offers an upload into the folder on screen, with the field's config" do
    target = Map.new(open_select(%{}, true).assigns.upload_target)

    assert target["data-kind"] == "image_picker"
    assert target["data-component-id"] == "image-picker"
    assert target["data-config-target"] == "default"
    assert is_binary(target["data-folder"])
  end

  test "no upload outside a form, where nothing would deliver it back to the picker" do
    assert open_select(%{}).assigns.upload_target == nil
  end

  describe "a big folder" do
    setup do
      user = Brando.Factory.insert(:random_user)

      for n <- 1..120 do
        Brando.Factory.insert(:image,
          creator_id: user.id,
          status: :processed,
          path: "images/site/default/picker-#{n}.jpg"
        )
      end

      :ok
    end

    test "renders a page of rows at a time" do
      socket = open_select(%{})
      assert socket.assigns.image_count == 120
      assert socket.assigns.rendered_count == 100

      {:noreply, socket} = ImagePicker.handle_event("load_more_images", %{}, socket)
      assert socket.assigns.rendered_count == 120

      # Nothing left: another request changes nothing.
      {:noreply, socket} = ImagePicker.handle_event("load_more_images", %{}, socket)
      assert socket.assigns.rendered_count == 120
    end

    test "keeps no rows once closed" do
      {:noreply, socket} = ImagePicker.handle_event("picker_closed", %{}, open_select(%{}))

      refute socket.assigns.opened?
      assert socket.assigns.rendered_count == 0
      assert socket.assigns.visible_item_ids == []
    end
  end

  defp picks(socket) do
    for ["b:image_picker:pick", payload] <- Phoenix.LiveView.Utils.get_push_events(socket), do: payload
  end

  describe "the whole library, for one field's pick" do
    @meta_target "image:Brando.Pages.Page:meta_image"

    setup do
      user = Brando.Factory.insert(:random_user)

      cover =
        Brando.Factory.insert(:image,
          creator_id: user.id,
          status: :processed,
          config_target: "default",
          path: "images/articles/cover/harbour.jpg"
        )

      {:ok, user: user, cover: cover}
    end

    defp open_for_field(user, params \\ %{}) do
      socket = picker()

      socket = %{
        socket
        | assigns: Map.merge(socket.assigns, %{id: "image-picker", upload_in_form?: true, current_user: user})
      }

      {:ok, socket} =
        ImagePicker.update(
          Map.merge(%{config_target: @meta_target, event_target: nil, multi: false, selected_images: []}, params),
          socket
        )

      socket
    end

    test "opens on the field's own images, and offers the rest", %{user: user} do
      socket = open_for_field(user)

      assert socket.assigns.scope == :field
      assert socket.assigns.library_offered?
      assert socket.assigns.upload_root == "images/meta"
      assert socket.assigns.image_count == 0
    end

    test "is not offered to a pick of several, or without an editor", %{user: user} do
      refute open_for_field(user, %{multi: true}).assigns.library_offered?
      refute open_for_field(nil).assigns.library_offered?

      {:noreply, socket} = ImagePicker.handle_event("set_scope", %{"scope" => "library"}, open_for_field(nil))
      assert socket.assigns.scope == :field
    end

    test "lists the library from its root, without an upload", %{user: user, cover: cover} do
      {:noreply, socket} = ImagePicker.handle_event("set_scope", %{"scope" => "library"}, open_for_field(user))

      assert socket.assigns.scope == :library
      assert socket.assigns.upload_root == "images"
      assert socket.assigns.upload_target == nil
      assert "articles" in socket.assigns.child_folders

      {:noreply, socket} = ImagePicker.handle_event("go_folder", %{"folder" => "articles/cover"}, socket)
      assert cover.id in socket.assigns.visible_item_ids
    end

    test "a field that sends its target as a tuple is offered the library too", %{user: user} do
      socket = open_for_field(user, %{config_target: {"image", Brando.Pages.Page, :meta_image}})

      assert socket.assigns.config_target == @meta_target
      assert socket.assigns.library_offered?
    end

    test "Root in a folder of the field's own goes to the field's root", %{user: user} do
      Brando.Factory.insert(:image,
        creator_id: user.id,
        status: :processed,
        config_target: @meta_target,
        path: "images/meta/sub/one.jpg"
      )

      {:noreply, socket} = ImagePicker.handle_event("go_folder", %{"folder" => "sub"}, open_for_field(user))
      assert {socket.assigns.scope, socket.assigns.current_folder} == {:field, "sub"}

      {:noreply, socket} = ImagePicker.handle_event("picker_go_root", %{}, socket)
      assert {socket.assigns.scope, socket.assigns.current_folder} == {:field, ""}
    end

    test "opening again returns to the field's last folder and keeps folders made in it", %{user: user} do
      Brando.Factory.insert(:image,
        creator_id: user.id,
        status: :processed,
        config_target: @meta_target,
        path: "images/meta/sub/one.jpg"
      )

      {:noreply, socket} = ImagePicker.handle_event("go_folder", %{"folder" => "sub"}, open_for_field(user))
      {:noreply, socket} = ImagePicker.handle_event("create_folder", %{"folder" => %{"name" => "fresh"}}, socket)
      assert socket.assigns.current_folder == "sub/fresh"
      {:noreply, socket} = ImagePicker.handle_event("go_folder", %{"folder" => "sub"}, socket)
      {:noreply, socket} = ImagePicker.handle_event("picker_closed", %{}, socket)

      {:ok, socket} =
        ImagePicker.update(%{config_target: @meta_target, event_target: nil, multi: false, selected_images: []}, socket)

      assert socket.assigns.current_folder == "sub"
      assert "sub/fresh" in socket.assigns.child_folders
    end

    test "a folder browsed for one field is not where another field's opening starts", %{user: user} do
      Brando.Factory.insert(:image,
        creator_id: user.id,
        status: :processed,
        config_target: @meta_target,
        path: "images/meta/sub/one.jpg"
      )

      {:noreply, socket} = ImagePicker.handle_event("go_folder", %{"folder" => "sub"}, open_for_field(user))
      {:noreply, socket} = ImagePicker.handle_event("picker_closed", %{}, socket)

      {:ok, other} =
        ImagePicker.update(%{config_target: "default", event_target: nil, multi: false, selected_images: []}, socket)

      assert {other.assigns.current_folder, other.assigns.custom_folders} == {"", []}
      refute "sub" in other.assigns.folders

      {:ok, back} =
        ImagePicker.update(%{config_target: @meta_target, event_target: nil, multi: false, selected_images: []}, other)

      assert back.assigns.current_folder == "sub"
    end

    test "a copy ready after the picker opened for another field is not handed to that field", %{user: user} do
      picked = Brando.Factory.insert(:image, creator_id: user.id, config_target: @meta_target, status: :processed)
      field_a = %Phoenix.LiveComponent.CID{cid: 11}
      field_b = %Phoenix.LiveComponent.CID{cid: 22}

      socket = open_for_field(user, %{event_target: field_a})
      origin = {socket.assigns.open_generation, socket.assigns.event_target, socket.assigns.pick_values}

      # Still open for field A: the copy goes to A
      {:noreply, same} = ImagePicker.handle_async(:pick_library_image, {:ok, {origin, {:ok, picked}}}, socket)
      assert picks(same) == [%{id: picked.id, target: "11", values: %{}}]

      # Opened for field B in the meantime: dropped
      {:ok, reopened} =
        ImagePicker.update(
          %{config_target: @meta_target, event_target: field_b, multi: false, selected_images: []},
          socket
        )

      {:noreply, later} = ImagePicker.handle_async(:pick_library_image, {:ok, {origin, {:ok, picked}}}, reopened)
      assert picks(later) == []
    end

    test "Root and Up at the field's root lead into the library", %{user: user} do
      socket = open_for_field(user)

      {:noreply, at_root} = ImagePicker.handle_event("picker_go_root", %{}, socket)
      assert {at_root.assigns.scope, at_root.assigns.current_folder} == {:library, ""}

      # The folder above images/meta is the library's root
      {:noreply, up} = ImagePicker.handle_event("picker_go_parent", %{}, socket)
      assert {up.assigns.scope, up.assigns.current_folder} == {:library, ""}

      # Opening it again starts on the field's own images
      {:ok, reopened} =
        ImagePicker.update(
          %{config_target: @meta_target, event_target: nil, multi: false, selected_images: []},
          at_root
        )

      assert reopened.assigns.scope == :field
    end
  end
end
