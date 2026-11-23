defmodule BrandoAdmin.Components.Form.ImageDrawerCopyTest do
  # "Save as new copy" in the image editor opened from an image field's
  # drawer. The copy goes through the form's editor upload, as from a block,
  # and `Form.refocus_image_editor_copy/2` gives it the editor's focal point
  # before the field takes it.
  use ExUnit.Case, async: true
  use Brando.ConnCase

  import Phoenix.Component, only: [to_form: 1]

  alias Brando.Factory
  alias Brando.Images.Focal
  alias BrandoAdmin.Components.Form
  alias Ecto.Changeset
  alias Phoenix.Component

  setup do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)
    {:ok, user: user, page: page}
  end

  defp drawer_socket(ctx, image) do
    edit_image = %{
      id: image.id,
      path: [],
      field: :meta_image,
      relation_field: :meta_image_id,
      image: image,
      schema: Brando.Pages.Page
    }

    %Phoenix.LiveView.Socket{}
    |> Component.assign(:form, to_form(Changeset.change(ctx.page)))
    |> Component.assign(:entry, ctx.page)
    |> Component.assign(:schema, Brando.Pages.Page)
    |> Component.assign(:singular, "page")
    |> Component.assign(:current_user, ctx.user)
    |> Component.assign(:processing_images, [])
    |> Component.assign(:blocks_wanting_entry, %{})
    |> Component.assign(:updated_entry_assocs, %{})
    |> Component.assign(:editing_image?, true)
    |> Component.assign(:editing_video?, false)
    |> Component.assign(:editing_file?, false)
    |> Component.assign(:edit_image, edit_image)
    |> Component.assign(:edit_video, nil)
    |> Component.assign(:edit_file, nil)
    |> Component.assign(:image_changeset, Changeset.change(image))
    |> Component.assign(:video_changeset, nil)
    |> Component.assign(:file_changeset, nil)
  end

  # The upload has finished and made the copy. Its processing is queued, not
  # run: the factory image has no file.
  defp copy_made(socket, params, copy) do
    assert {:noreply, socket} = Form.handle_event("image_editor_save", Map.put(params, "mode", "new_copy"), socket)

    assert {:noreply, socket} =
             Oban.Testing.with_testing_mode(:manual, fn -> Form.refocus_image_editor_copy(socket, copy) end)

    socket
  end

  # An image picked from the library keeps the target it was uploaded for,
  # here another field's. Its copy is made for this field.
  test "the editor opened from the drawer makes its copy for the field", ctx do
    image = Factory.insert(:image, creator: ctx.user, config_target: "image:Brando.Pages.Fragment:cover")
    socket = drawer_socket(ctx, image)

    assert {:noreply, socket} = Form.handle_event("open_image_editor", %{"image_id" => image.id}, socket)

    assert [payload] =
             for(["b:image_editor:init", payload] <- Phoenix.LiveView.Utils.get_push_events(socket), do: payload)

    assert payload.image_id == image.id
    assert payload.config_target == Brando.Assets.ConfigTarget.serialize({"image", Brando.Pages.Page, :meta_image})
  end

  # As the Figma import places it: an untouched copy is cut where the
  # original is, not around the centre.
  test "a copy of an image in position mode takes the field with the point and mode", ctx do
    image = Factory.insert(:image, creator: ctx.user, focal: %{x: 75, y: 0, mode: :position})
    copy = Factory.insert(:image, creator: ctx.user)

    socket =
      ctx
      |> drawer_socket(image)
      |> copy_made(%{"focal_x" => 75, "focal_y" => 0, "focal_mode" => "position"}, copy)

    assert Changeset.get_change(socket.assigns.form.source, :meta_image_id) == copy.id
    assert socket.assigns.edit_image.image.id == copy.id
    assert socket.assigns.edit_image.image.focal == %Focal{x: 75, y: 0, mode: :position}
    assert Brando.Images.get_image!(copy.id).focal == %Focal{x: 75, y: 0, mode: :position}
    assert copy.id in socket.assigns.processing_images
  end

  test "a copy of an image in the ordinary mode keeps its point", ctx do
    image = Factory.insert(:image, creator: ctx.user, focal: %{x: 20, y: 30})
    copy = Factory.insert(:image, creator: ctx.user)

    socket =
      ctx
      |> drawer_socket(image)
      |> copy_made(%{"focal_x" => 20, "focal_y" => 30, "focal_mode" => "center"}, copy)

    assert Changeset.get_change(socket.assigns.form.source, :meta_image_id) == copy.id
    assert Brando.Images.get_image!(copy.id).focal == %Focal{x: 20, y: 30, mode: :center}
  end
end
