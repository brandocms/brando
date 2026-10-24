defmodule BrandoAdmin.Components.Form.DraftCaptureTest do
  use Brando.ConnCase, async: false
  alias Brando.DraftFixtures
  alias Brando.Drafts
  alias Brando.Drafts.Content
  alias BrandoAdmin.Components.Form.Drafts, as: FormDrafts
  alias Phoenix.Component

  setup do
    user = Brando.Factory.insert(:random_user)
    baseline = Map.put(DraftFixtures.payload(), "modules", %{})
    identity = Drafts.identity(Brando.Pages.Page, nil, user.id)
    checksum = Content.checksum(baseline)

    socket =
      %Phoenix.LiveView.Socket{}
      |> Component.assign(:schema, Brando.Pages.Page)
      |> Component.assign(:id, "page_form")
      |> Component.assign(:draft, %{
        id: Ecto.UUID.generate(),
        identity: identity,
        generation: 0,
        persisted: 0,
        baseline: checksum,
        checksum: checksum,
        base_fingerprint: "base",
        modules: %{},
        capture: nil,
        status: :ready,
        saved_at: nil
      })

    {:ok, socket: socket, baseline: baseline, identity: identity}
  end

  defp capture(socket, payload, kind \\ nil) do
    draft = socket.assigns.draft

    capture = %{
      id: Ecto.UUID.generate(),
      generation: draft.generation + 1,
      client_generation: 1,
      request_id: 1,
      main: payload["main"],
      expected: [{:block, "blocks"}, {:transformer, "items"}],
      parts: %{{:transformer, "items"} => payload["transformers"]["items"]},
      kind: kind
    }

    socket
    |> Component.assign(:draft, %{draft | capture: capture})
    |> FormDrafts.part(capture.id, :block, "blocks", payload["blocks"]["blocks"])
  end

  test "captures of initialized content never write a recovery copy", ctx do
    initialized = DraftFixtures.initialized(ctx.baseline)
    socket = ctx.socket |> capture(initialized) |> capture(initialized)
    assert socket.assigns.draft.status == :saved
    assert socket.assigns.draft.capture == nil
    assert Drafts.list(ctx.identity) == []
  end

  test "real edits keep their full payload and reverting to the saved content resolves them", ctx do
    initialized = DraftFixtures.initialized(ctx.baseline)
    edited = put_in(initialized, ["main", "title"], "Actual edit")
    socket = capture(ctx.socket, edited)
    assert [copy] = Drafts.list(ctx.identity)
    assert copy.payload == edited
    assert copy.checksum == Drafts.checksum(edited)

    socket = capture(socket, initialized)
    assert Drafts.list(ctx.identity) == []
    assert socket.assigns.draft.id != copy.id
    assert Drafts.get(ctx.identity, copy.id).payload == edited
  end

  test "a tab keeps later edits when another tab discards its equivalent recovery copy", ctx do
    edited = put_in(ctx.baseline, ["main", "title"], "Shared unsaved text")
    socket = capture(ctx.socket, edited)
    original_id = socket.assigns.draft.id
    version = Brando.Blueprint.Snapshot.get_current_version(Brando.Pages.Page)
    {:ok, other} = Drafts.write(ctx.identity, Ecto.UUID.generate(), 1, edited, "base", version)
    assert {:ok, _} = Drafts.discard(ctx.identity, other.id)
    assert Drafts.list(ctx.identity) == []

    later = put_in(edited, ["main", "title"], "Still editing in this tab")
    socket = capture(socket, later)
    assert [copy] = Drafts.list(ctx.identity)
    assert copy.id == socket.assigns.draft.id
    refute copy.id == original_id
    assert copy.payload == later
    assert Drafts.get(ctx.identity, original_id).payload == edited

    # A capture reply invalidated by an explicit save/reset cannot retry a write.
    assert FormDrafts.part(socket, "stale-capture", :block, "blocks", []) == socket
    assert Drafts.list(ctx.identity) == [copy]
  end

  # Another of the editor's tabs takes over (`LiveView.Form.Tabs`). A capture
  # that was under way has the browser's form from before the release: the
  # release's own capture is asked for again, and only that one is handed over.
  test "only the release's own capture is handed over", ctx do
    edited = put_in(ctx.baseline, ["main", "title"], "Typed before the release")

    socket =
      ctx.socket
      |> Component.update(:draft, &Map.merge(&1, %{candidates: [], open?: false}))
      |> Component.assign(:tab_editing?, false)
      |> Component.assign(:tab_release, %{to: self(), token: make_ref(), fields: ["title"]})
      |> capture(edited)

    refute_received {BrandoAdmin.LiveView.Form.Tabs, :handover, _, _}
    assert ["b:draft-release", %{id: "page_form"}] in Phoenix.LiveView.Utils.get_push_events(socket)
    assert socket.assigns.tab_release

    socket = capture(socket, put_in(edited, ["main", "title"], "Typed since"), :release)
    id = socket.assigns.draft.id
    assert_received {BrandoAdmin.LiveView.Form.Tabs, :handover, _, %{draft_id: handed, fields: ["title"]}}
    assert Drafts.get(ctx.identity, handed).payload["main"]["title"] == "Typed since"
    # this tab writes no more to the copy it handed over
    refute id == handed
    refute socket.assigns.tab_release
  end
end
