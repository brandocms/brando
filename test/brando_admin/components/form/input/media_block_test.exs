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
        block_templates: %{
          picture: %Blocks.PictureBlock.Data{},
          video: %Blocks.VideoBlock.Data{},
          gallery: nil,
          svg: %Blocks.SvgBlock.Data{code: "<svg/>"},
          file: nil
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
end
