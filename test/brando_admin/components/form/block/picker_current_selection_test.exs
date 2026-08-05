defmodule BrandoAdmin.Components.Form.Block.PickerCurrentSelectionTest do
  # Regression coverage for D6 — two block-level image pickers opened with
  # `selected_images: []` even though the block already had an image.
  #
  # The uploads skill's contract is "selection means current editing state":
  # reopening a picker must mark the asset the editor is currently showing, not
  # the one last written to the database, and not nothing at all. Every
  # entry-field picker already honoured it; `render_var`'s image var and the
  # video block's cover image did not — `render_var`'s own sibling
  # `set_file_target` got it right, which is what made the omission visible.
  #
  # `send_update/2` outside a LiveView process is just a message to `self()`,
  # so the payload each handler ships to the picker is directly assertable.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.Component, only: [to_form: 1]

  alias Brando.Factory
  alias BrandoAdmin.Components.Form.Input.RenderVar
  alias BrandoAdmin.Components.ImagePicker
  alias Ecto.Changeset
  alias Phoenix.Component

  defp var_socket(image_id) do
    var_form = to_form(Changeset.change(%Brando.Content.Var{type: :image}))

    socket =
      %Phoenix.LiveView.Socket{}
      |> Component.assign(:var, var_form)
      |> Component.assign(:image_id, image_id)
      |> Component.assign(:file_id, nil)

    # `:myself` is reserved, so assign/3 refuses it — the components read it as
    # the picker's `event_target`, so it has to be present.
    %{socket | assigns: Map.put(socket.assigns, :myself, %Phoenix.LiveComponent.CID{cid: 1})}
  end

  defp picker_payload do
    assert_receive {:phoenix, :send_update, {{ImagePicker, "image-picker"}, assigns}}
    assigns
  end

  describe "image var picker" do
    test "carries the var's current image id into the picker" do
      image = Factory.insert(:image, creator: Factory.insert(:random_user))

      assert {:noreply, _socket} =
               RenderVar.handle_event("set_target", %{}, var_socket(image.id))

      assert picker_payload().selected_images == [image.id]
    end

    test "carries an id that is still only a pending (unsaved) selection" do
      # The id assigned by `select_image` is the raw string from the DOM event;
      # the picker normalizes ids before comparing, so this must survive as-is
      # rather than being dropped for not being an integer.
      assert {:noreply, _socket} =
               RenderVar.handle_event("set_target", %{}, var_socket("123"))

      assert picker_payload().selected_images == ["123"]
    end

    test "sends an empty selection when the var has no image" do
      assert {:noreply, _socket} =
               RenderVar.handle_event("set_target", %{}, var_socket(nil))

      assert picker_payload().selected_images == []
    end

    test "the file sibling it was compared against still behaves the same" do
      # Guards the reference implementation: if `set_file_target` ever regresses
      # to `[]` the image fix above loses the precedent it was modelled on.
      socket =
        nil
        |> var_socket()
        |> Component.assign(:file_id, 77)

      assert {:noreply, _socket} = RenderVar.handle_event("set_file_target", %{}, socket)

      assert_receive {:phoenix, :send_update, {{BrandoAdmin.Components.FilePicker, "file-picker"}, assigns}}

      assert assigns.selected_files == [77]
    end
  end
end
