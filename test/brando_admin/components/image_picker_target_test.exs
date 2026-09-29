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
end
