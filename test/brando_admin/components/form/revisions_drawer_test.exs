defmodule BrandoAdmin.Components.Form.RevisionsDrawerTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.Revisions.Revision
  alias BrandoAdmin.Components.Form.RevisionsDrawer
  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.LiveView.JS

  test "initializes safely before a new entry has been persisted" do
    form =
      %Brando.Pages.Page{}
      |> Ecto.Changeset.change()
      |> Phoenix.Component.to_form(as: :page)

    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}

    assert {:ok, updated_socket} =
             RevisionsDrawer.update(
               %{
                 id: "revisions-drawer",
                 entry_id: nil,
                 form: form,
                 status: :closed
               },
               socket
             )

    assert updated_socket.assigns.entry_type == Brando.Pages.Page
    assert is_integer(updated_socket.assigns.schema_version)
  end

  test "renders accessible metadata and safe system attribution without snapshot blobs" do
    revision = %Revision{
      active: false,
      creator: nil,
      description: "Ready for launch",
      inserted_at: ~U[2026-07-15 12:00:00Z],
      protected: false,
      revision: 12,
      scheduled: true,
      schema_version: 2
    }

    html =
      render_component(&RevisionsDrawer.render/1, %{
        id: "revisions-drawer",
        close: %JS{},
        form_cid: "form-target",
        myself: "drawer-target",
        preview_revision: nil,
        revision_data: AsyncResult.ok(%{revisions: [revision], has_more: false}),
        schema_version: 2,
        show_publish_at: nil,
        status: :open
      })

    assert html =~ "<thead>"
    assert html =~ "Store current editor state"
    assert html =~ "System"
    assert html =~ "Scheduled"
    assert html =~ ~s(id="preview-revision-12")
    assert html =~ "Unsaved editor changes will be replaced"
    assert html =~ "Cancel schedule"
    refute html =~ "Delete version"
  end

  test "renders a retry action when loading fails" do
    failed_result =
      AsyncResult.loading()
      |> AsyncResult.failed(:failed_to_load_revisions)

    html =
      render_component(&RevisionsDrawer.render/1, %{
        id: "revisions-drawer",
        close: %JS{},
        form_cid: "form-target",
        myself: "drawer-target",
        preview_revision: nil,
        revision_data: failed_result,
        schema_version: 2,
        show_publish_at: nil,
        status: :open
      })

    assert html =~ "Failed to load revisions"
    assert html =~ "Try again"
    assert html =~ ~s(phx-click="fetch_revisions")
  end
end
