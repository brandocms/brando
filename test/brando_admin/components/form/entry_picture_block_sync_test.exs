defmodule BrandoAdmin.Components.Form.EntryPictureBlockSyncTest do
  # A block whose module previews the entry's own picture (`{% picture
  # entry.meta_image {…} %}`) is on the form's entry fan-out for that field.
  # Picking, uploading, removing or resetting the image in the form commits the
  # relation's id; the block reads the relation, so the form delivers the
  # relation itself, and the preview follows.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.Component, only: [to_form: 1]

  alias Brando.Factory
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Block
  alias Ecto.Changeset
  alias Phoenix.Component

  @code ~s(<header>{% picture entry.meta_image {size: "xlarge"} %}</header>)
  @block_ref {Block, "block-preview"}

  setup do
    user = Factory.insert(:random_user)
    first = Factory.insert(:image, creator: user, path: "images/meta/first.jpg")
    second = Factory.insert(:image, creator: user, path: "images/meta/second.jpg")
    page = Factory.insert(:page, creator: user, meta_image_id: first.id)
    page = %{page | meta_image: first}
    {:ok, user: user, page: page, first: first, second: second}
  end

  defp form_socket(page, user, edit_image) do
    %Phoenix.LiveView.Socket{}
    |> Component.assign(:form, to_form(Changeset.change(page)))
    |> Component.assign(:entry, page)
    |> Component.assign(:schema, Brando.Pages.Page)
    |> Component.assign(:singular, "page")
    |> Component.assign(:current_user, user)
    |> Component.assign(:processing_images, [])
    |> Component.assign(:editing_image?, false)
    |> Component.assign(:editing_video?, false)
    |> Component.assign(:editing_file?, false)
    |> Component.assign(:edit_image, edit_image)
    |> Component.assign(:edit_video, nil)
    |> Component.assign(:edit_file, nil)
    |> Component.assign(:updated_entry_assocs, %{})
    |> Component.assign(:blocks_wanting_entry, %{@block_ref => ["meta_image"]})
  end

  defp block_socket(page) do
    %Phoenix.LiveView.Socket{}
    |> Component.assign(:entry, page)
    |> Component.assign(:liquid_splits, Block.liquid_splits(@code, [], page))
  end

  defp preview_src(block_socket) do
    Enum.find_value(block_socket.assigns.liquid_splits, fn
      {:entry_picture, "entry.meta_image", src} -> src
      _ -> nil
    end)
  end

  # What the form sent the block, applied as LiveView would
  defp deliver_to_block(block_socket) do
    assert_received {:phoenix, :send_update, {@block_ref, %{event: "update_entry_field"} = update}}
    {:ok, block_socket} = Block.update(update, block_socket)
    block_socket
  end

  test "picking another image moves the block's preview to it", ctx do
    %{page: page, user: user, second: second} = ctx
    block = block_socket(page)
    assert preview_src(block) =~ "first.jpg"

    edit_image = %{path: [], field: :meta_image, relation_field: :meta_image_id, image: nil}

    {:ok, _form} =
      Form.update(
        %{event: "entry_field_upload_complete", asset_type: :image, field: :meta_image, path: [], asset: second},
        form_socket(page, user, edit_image)
      )

    assert block |> deliver_to_block() |> preview_src() =~ "second.jpg"
  end

  # The live preview merges `updated_entry_assocs` over the entry, so an image
  # picked earlier would hide the one uploaded now.
  test "an upload replaces the image the preview shows", ctx do
    %{page: page, user: user, first: first, second: second} = ctx
    edit_image = %{path: [], field: :meta_image, relation_field: :meta_image_id, image: first}
    socket = page |> form_socket(user, edit_image) |> Component.assign(:updated_entry_assocs, %{meta_image: first})

    {:ok, form} =
      Form.update(
        %{event: "entry_field_upload_complete", asset_type: :image, field: :meta_image, path: [], asset: second},
        socket
      )

    assert form.assigns.updated_entry_assocs == %{meta_image: second}
  end

  # The drawer's save changes the image the field shows; the preview's copy
  # of it follows, or the title edited there never reaches the preview.
  test "saving the image's drawer refreshes the image the preview shows", ctx do
    %{page: page, user: user} = ctx
    image = Factory.insert(:image, creator: user, focal: %Brando.Images.Focal{x: 50, y: 50}, status: :processed)
    edit_image = %{path: [], field: :meta_image, relation_field: :meta_image_id, image: image}

    socket =
      page
      |> form_socket(user, edit_image)
      |> Component.assign(sync_assigns())
      |> Component.assign(:updated_entry_assocs, %{meta_image: image})

    params = %{"image" => %{"title" => %{"en" => "Example Hotel lobby"}}}
    {:noreply, form} = Form.handle_event("save_image", params, socket)

    assert form.assigns.updated_entry_assocs.meta_image.title == %{"en" => "Example Hotel lobby"}
  end

  # The preview merges a relation this editor picked (a select with
  # `update_relation`) over the entry, and otherwise preloads only a relation
  # not loaded yet; another editor's pick replaces both.
  for {held, page_parent} <- [{"one this editor picked", :not_loaded}, {"a loaded one", :loaded}] do
    test "another editor's pick replaces #{held}", ctx do
      %{page: page, user: user} = ctx
      parent = Factory.insert(:page, creator: user, title: "Example Hotel")

      {page, assocs} =
        if unquote(page_parent) == :loaded, do: {%{page | parent: nil}, %{}}, else: {page, %{parent: nil}}

      socket =
        page
        |> form_socket(user, nil)
        |> Component.assign(sync_assigns())
        |> Component.assign(:updated_entry_assocs, assocs)

      changes = [%{field: :parent_id, value: parent.id, assoc?: false, clock: {1, "remote"}}]

      {:ok, form} = Form.update(%{event: "apply_remote_field_changes", changes: changes}, socket)

      assert form.assigns.updated_entry_assocs.parent.id == parent.id
    end
  end

  defp sync_assigns do
    [
      tiptap_epoch: "mounted-form",
      dirty_fields: [],
      synced_values: %{},
      unshipped_fields: MapSet.new(),
      replaced_values: %{},
      held_remote: %{},
      field_clocks: %{},
      live_preview_active?: false
    ]
  end

  # Another editor's pick arrives as the image's id (`apply_remote/2`); the
  # block reads the relation, so that is what it gets.
  test "another editor's pick moves the block's preview to it", ctx do
    %{page: page, user: user, second: second} = ctx
    block = block_socket(page)
    socket = page |> form_socket(user, nil) |> Component.assign(sync_assigns())

    changes = [%{field: :meta_image_id, value: second.id, assoc?: false, clock: {1, "remote"}}]

    {:ok, _form} = Form.update(%{event: "apply_remote_field_changes", changes: changes}, socket)

    assert block |> deliver_to_block() |> preview_src() =~ "second.jpg"
  end

  test "removing the image clears the block's preview", ctx do
    %{page: page, user: user} = ctx
    block = block_socket(page)

    {:ok, _form} =
      Form.update(%{event: "clear_entry_field_asset", field: :meta_image, path: []}, form_socket(page, user, nil))

    assert block |> deliver_to_block() |> preview_src() == ""
  end

  test "resetting the image in its drawer clears the block's preview", ctx do
    %{page: page, user: user, first: first} = ctx
    block = block_socket(page)
    edit_image = %{path: [], field: :meta_image, relation_field: :meta_image_id, image: first}

    {:noreply, _form} = Form.handle_event("reset_image_field", %{}, form_socket(page, user, edit_image))

    assert block |> deliver_to_block() |> preview_src() == ""
  end
end
