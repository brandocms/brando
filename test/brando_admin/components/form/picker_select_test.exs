defmodule BrandoAdmin.Components.Form.PickerSelectTest do
  # Regression coverage for B7 — picking an existing asset in a picker had
  # different durability than uploading one.
  #
  # An UPLOAD commits the FK immediately through `commit_entry_field_asset/4`.
  # A SELECT only assigned `edit_image` / `image_changeset`; the id reached the
  # entry changeset solely through the drawer's form submit, which is dispatched
  # by the close BUTTON (`close_image/1`). Dismiss the drawer any other way —
  # Esc, the backdrop, navigating away — and the selection was silently lost.
  #
  # Esc/backdrop are client-side, so what is asserted here is the invariant that
  # makes every dismissal path safe: the select itself commits the FK, so no
  # dismissal path has anything left to lose.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.Component, only: [to_form: 1]

  alias Brando.Factory
  alias BrandoAdmin.Components.Form
  alias Ecto.Changeset
  alias Phoenix.Component

  setup do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)
    {:ok, user: user, page: page, image: Factory.insert(:image, creator: user)}
  end

  defp form_socket(page, user, edit_assigns) do
    %Phoenix.LiveView.Socket{}
    |> Component.assign(:form, to_form(Changeset.change(page)))
    |> Component.assign(:entry, page)
    |> Component.assign(:schema, Brando.Pages.Page)
    |> Component.assign(:singular, "page")
    |> Component.assign(:current_user, user)
    |> Component.assign(:processing_images, [])
    # drawer state `assign_drawer_recovery_state/1` destructures
    |> Component.assign(:editing_image?, true)
    |> Component.assign(:editing_video?, false)
    |> Component.assign(:editing_file?, false)
    |> Component.assign(:edit_image, nil)
    |> Component.assign(:edit_video, nil)
    |> Component.assign(:edit_file, nil)
    |> Component.assign(edit_assigns)
  end

  defp committed_fk(socket, key) do
    socket.assigns.form.source |> Changeset.apply_changes() |> Map.get(key)
  end

  test "selecting an image commits meta_image_id to the entry changeset", ctx do
    %{page: page, user: user, image: image} = ctx

    socket =
      form_socket(page, user, %{
        edit_image: %{path: [], field: :meta_image, relation_field: :meta_image_id, image: nil}
      })

    assert {:ok, socket} = Form.update(%{action: :update_edit_image, image: image}, socket)

    assert committed_fk(socket, :meta_image_id) == image.id,
           "a picker select must commit the FK, not wait for the drawer's submit"

    # the drawer still gets its editing state
    assert socket.assigns.edit_image.image.id == image.id
    assert socket.assigns.image_changeset.data.id == image.id
  end

  test "the committed FK is a change, so the entry save writes it", ctx do
    %{page: page, user: user, image: image} = ctx

    socket =
      form_socket(page, user, %{
        edit_image: %{path: [], field: :meta_image, relation_field: :meta_image_id, image: nil}
      })

    assert {:ok, socket} = Form.update(%{action: :update_edit_image, image: image}, socket)

    # in `changes`, not merely applied into `data` — otherwise nothing is written
    assert socket.assigns.form.source.changes[:meta_image_id] == image.id

    assert {:ok, saved} = Brando.Repo.update(Map.put(socket.assigns.form.source, :action, nil))
    assert saved.meta_image_id == image.id
  end

  test "a block-level pick is left to commit_ref_data and does not touch the entry", ctx do
    %{page: page, user: user, image: image} = ctx

    socket =
      form_socket(page, user, %{
        edit_image: %{
          path: [],
          field: nil,
          relation_field: nil,
          image: nil,
          block_target: {BrandoAdmin.Components.Form.Block, "block-abc"}
        }
      })

    assert {:ok, socket} = Form.update(%{action: :update_edit_image, image: image}, socket)

    assert socket.assigns.form.source.changes == %{}
    assert socket.assigns.edit_image.image.id == image.id
  end

  test "an edit_image with no field is a no-op on the entry changeset", ctx do
    %{page: page, user: user, image: image} = ctx

    socket = form_socket(page, user, %{edit_image: %{path: [], field: nil, image: nil}})

    assert {:ok, socket} = Form.update(%{action: :update_edit_image, image: image}, socket)
    assert socket.assigns.form.source.changes == %{}
  end
end
