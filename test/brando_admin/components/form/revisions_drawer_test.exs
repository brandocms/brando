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
      inserted_at: ~N[2026-07-15 12:00:00],
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
        revision_data:
          AsyncResult.ok(%{
            revisions: [
              revision,
              %{
                revision
                | revision: 13,
                  active: true,
                  scheduled: false,
                  protected: true,
                  inserted_at: ~U[2026-07-15 12:00:00Z]
              }
            ],
            has_more: false
          }),
        schema_version: 2,
        show_publish_at: nil,
        status: :open,
        tab: :revisions,
        activity: nil,
        comparison: nil
      })

    assert html =~ "<thead>"
    assert html =~ "Store current editor state"
    assert html =~ "System"
    assert html =~ "Scheduled"
    assert html =~ ~r/>\s*Active\s*<\/span>/
    assert html =~ ~r/>\s*Inactive\s*<\/span>/
    assert html =~ "Protected"
    assert html =~ ~s(datetime="2026-07-15T12:00:00Z")
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
        status: :open,
        tab: :revisions,
        activity: nil,
        comparison: nil
      })

    assert html =~ "Failed to load revisions"
    assert html =~ "Try again"
    assert html =~ ~s(phx-click="fetch_revisions")
  end

  test "the activity tab lists what happened to the entry, with who and when" do
    user = %Brando.Users.User{id: 7, name: "Ola Hansen"}
    now = DateTime.utc_now()

    events = [
      %Brando.Activity.Event{
        id: 2,
        action: :revision_restored,
        source: :admin,
        user: user,
        schema: "Elixir.Brando.Pages.Page",
        entry_id: 1,
        revision: 7,
        details: %{"replaced" => 11},
        fields: [],
        inserted_at: now
      },
      %Brando.Activity.Event{
        id: 1,
        action: :published,
        source: :scheduler,
        user: user,
        schema: "Elixir.Brando.Pages.Page",
        entry_id: 1,
        revision: 3,
        details: %{"scheduled" => true},
        fields: [],
        inserted_at: DateTime.add(now, -86_400 * 3, :second)
      }
    ]

    html =
      render_component(&RevisionsDrawer.render/1, %{
        id: "revisions-drawer",
        close: %JS{},
        form_cid: "form-target",
        myself: "drawer-target",
        preview_revision: nil,
        revision_data: AsyncResult.ok(%{revisions: [], has_more: false}),
        schema_version: 2,
        show_publish_at: nil,
        status: :open,
        tab: :activity,
        activity: %{events: events, states: %{}, has_more: true},
        comparison: nil
      })

    assert html =~ "Entry history"
    assert html =~ ~s(aria-selected="true")
    assert html =~ "Restored revision #7"
    assert html =~ "by Ola Hansen"
    assert html =~ "Replaced revision #11"
    assert html =~ "Compare with #11"
    assert html =~ "by scheduled publishing"
    assert html =~ "Activated revision #3, as scheduled"
    assert html =~ "Show older activity"
    refute html =~ "Store current editor state"
  end

  test "an agent's change shows the kind of actor, who approved it and, to them, its proposal" do
    user = %Brando.Users.User{id: 7, name: "Ola Hansen"}
    proposal_id = Ecto.UUID.generate()

    event = %Brando.Activity.Event{
      id: 3,
      action: :updated,
      source: :mcp,
      user: user,
      approver_id: 7,
      approver: user,
      proposal_id: proposal_id,
      schema: "Elixir.Brando.Pages.Page",
      entry_id: 1,
      revision: 2,
      details: %{"client" => "Claude Code"},
      fields: ["title"],
      inserted_at: DateTime.utc_now()
    }

    render = fn viewer ->
      render_component(&RevisionsDrawer.render/1, %{
        id: "revisions-drawer",
        close: %JS{},
        form_cid: "form-target",
        myself: "drawer-target",
        preview_revision: nil,
        revision_data: AsyncResult.ok(%{revisions: [], has_more: false}),
        schema_version: 2,
        show_publish_at: nil,
        status: :open,
        tab: :activity,
        activity: %{events: [event], states: %{}, viewer: viewer, has_more: false},
        comparison: nil
      })
    end

    html = render.(%{user_id: 7, assistant?: true})
    assert html =~ "by Claude Code"
    assert html =~ ~s(<span class="activity-kind" data-kind="mcp">MCP</span>)
    assert html =~ "Approved by Ola Hansen"
    assert html =~ ~s(href="/admin/assistant/connected/#{proposal_id}")

    # Only the person who applied it can open the proposal
    refute render.(%{user_id: 8, assistant?: true}) =~ "/admin/assistant/connected/"
    refute render.(%{user_id: 7, assistant?: false}) =~ "/admin/assistant/connected/"
  end
end
