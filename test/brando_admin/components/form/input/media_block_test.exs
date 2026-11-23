defmodule BrandoAdmin.Components.Form.Input.MediaBlockTest do
  # A media slot turns into one of the types its module lists, and only
  # those, whatever type the event names.
  use ExUnit.Case, async: true

  alias Brando.Villain.Blocks
  alias BrandoAdmin.Components.Form.Input.Blocks.MediaBlock

  defp socket(available) do
    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        available_blocks: available,
        media_data: %Blocks.MediaBlock.Data{
          template_picture: %Blocks.PictureBlock.Data{},
          template_video: %Blocks.VideoBlock.Data{},
          template_svg: %Blocks.SvgBlock.Data{code: "<svg/>"}
        },
        target_ref: {BrandoAdmin.Components.Form.Block, "block-x"},
        ref_name: "visual",
        ref_description: nil,
        uid: "refuid"
      }
    }
  end

  test "a listed type replaces the slot" do
    MediaBlock.handle_event("select_block", %{"block" => "picture"}, socket(["picture"]))
    assert_received {:phoenix, :send_update, {_, %{event: "update_ref", ref: %{data: %Blocks.PictureBlock{}}}}}
  end

  test "a type the module does not list is refused" do
    MediaBlock.handle_event("select_block", %{"block" => "video"}, socket(["picture"]))
    refute_received {:phoenix, :send_update, _}
  end

  test "a media ref without a template for the type gets empty data, as it always has" do
    socket = put_in(socket(["picture", "video", "file"]).assigns.media_data, %Blocks.MediaBlock.Data{})

    MediaBlock.handle_event("select_block", %{"block" => "picture"}, socket)
    assert_received {:phoenix, :send_update, {_, %{event: "update_ref", ref: %{data: %Blocks.PictureBlock{data: nil}}}}}

    MediaBlock.handle_event("select_block", %{"block" => "video"}, put_in(socket.assigns.media_data, nil))
    assert_received {:phoenix, :send_update, {_, %{event: "update_ref", ref: %{data: %Blocks.VideoBlock{data: nil}}}}}

    MediaBlock.handle_event("select_block", %{"block" => "file"}, socket)

    assert_received {:phoenix, :send_update,
                     {_, %{event: "update_ref", ref: %{data: %Blocks.FileBlock{data: %Blocks.FileBlock.Data{}}}}}}
  end
end
