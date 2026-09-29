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
end
