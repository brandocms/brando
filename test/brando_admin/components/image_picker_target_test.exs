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
end
