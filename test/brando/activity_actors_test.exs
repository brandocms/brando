defmodule Brando.ActivityActorsTest do
  # Who made each change: a person, the Assistant, a tool connected over MCP
  # or an automatic job, with the proposal a change came from and the user
  # who approved and applied it.
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Activity
  alias Brando.Activity.Event
  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.Tools
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page
  alias Brando.Repo

  setup do
    {:ok, %{user: Factory.insert(:random_user)}}
  end

  defp create_page(user, title \\ "Sommerro") do
    {:ok, page} =
      Pages.create_page(
        %{
          title: title,
          uri: "actors-#{System.unique_integer([:positive])}",
          language: "en",
          template: "default.html",
          status: :draft
        },
        user
      )

    page
  end

  defp events(page) do
    Repo.all(from(e in Event, where: e.schema == ^to_string(Page) and e.entry_id == ^page.id, order_by: [asc: e.id]))
  end

  # Prepared through the same tools as the Assistant and BrandoMCP, then
  # approved and applied by `user`.
  defp apply_proposal(page, user, origin, client \\ nil) do
    op = %{
      "op" => "set_fields",
      "target" => %{"content_type" => "Brando.Pages.Page", "id" => page.id},
      "fields" => %{"title" => page.title <> " hotel"}
    }

    context = %Tools.Context{actor: user, origin: origin, client: client}

    {:ok, %{proposal_id: id, version: version}} =
      Tools.call("prepare_proposal", %{"summary" => "Retitle", "operations" => [op]}, context)

    {:ok, _} = Proposals.approve(id, version, user)
    {:ok, _} = Proposals.apply(id, version, user)
    id
  end

  test "a person's save is theirs, with no proposal and no approver", %{user: user} do
    page = create_page(user)
    {:ok, _} = Pages.update_page(page.id, %{title: "Sommerro hotel"}, user)

    assert [created, updated] = events(page)

    for event <- [created, updated] do
      assert %{source: :admin, user_id: user_id, proposal_id: nil, approver_id: nil} = event
      assert user_id == user.id
      assert Activity.actor_kind(event) == :person
    end
  end

  test "an Assistant proposal names the proposal and the user who applied it", %{user: user} do
    page = create_page(user)
    id = apply_proposal(page, user, :assistant)

    assert [_created, event] = events(page)
    assert event.action == :updated
    assert event.source == :assistant
    assert event.proposal_id == id
    assert event.approver_id == user.id
    assert event.user_id == user.id
    assert Activity.actor_kind(event) == :assistant
  end

  test "an MCP proposal names the tool, the proposal and the user who applied it", %{user: user} do
    page = create_page(user)
    id = apply_proposal(page, user, :mcp, "Claude Code")

    assert [_created, event] = events(page)
    assert event.source == :mcp
    assert event.details["client"] == "Claude Code"
    assert event.proposal_id == id
    assert event.approver_id == user.id
    assert Activity.actor_kind(event) == :mcp
  end

  test "undoing a proposal is recorded against it, by the user who undid it", %{user: user} do
    page = create_page(user)
    id = apply_proposal(page, user, :mcp, "Claude Code")
    assert {:ok, _} = Proposals.undo(id, user)

    assert [_created, _applied, undone] = events(page)
    assert undone.action == :revision_restored
    assert undone.source == :mcp
    assert undone.proposal_id == id
    assert undone.approver_id == user.id
    assert undone.details["undo_proposal"] == true
  end

  test "attribution ends with the proposal: the next save is the person's again", %{user: user} do
    page = create_page(user)
    apply_proposal(page, user, :assistant)
    {:ok, _} = Pages.update_page(page.id, %{meta_description: "By the sea"}, user)

    assert %{source: :admin, proposal_id: nil, approver_id: nil} = List.last(events(page))
  end

  test "scheduled publishing is an automatic job, for the user who scheduled it", %{user: user} do
    page = create_page(user)

    assert :ok =
             perform_job(Brando.Worker.EntryPublisher, %{
               "schema" => to_string(Page),
               "id" => page.id,
               "status" => "published",
               "user_id" => user.id
             })

    assert [_created, event] = events(page)
    assert event.action == :published
    assert event.source == :scheduler
    assert event.user_id == user.id
    assert event.proposal_id == nil
    assert event.approver_id == nil
    assert Activity.actor_kind(event) == :task
  end

  test "the log is filtered by kind and by MCP client", %{user: user} do
    by_hand = create_page(user, "By hand")
    assistant = create_page(user, "Assistant")
    claude = create_page(user, "Claude")
    cursor = create_page(user, "Cursor")
    apply_proposal(assistant, user, :assistant)
    apply_proposal(claude, user, :mcp, "Claude Code")
    apply_proposal(cursor, user, :mcp, "Cursor")
    {:ok, _} = Pages.update_page(by_hand.id, %{title: "By hand, scheduled"}, :system)

    titles = fn filters ->
      filters |> Activity.list() |> Enum.map(& &1.title) |> Enum.sort()
    end

    assert titles.(%{actor: :assistant}) == ["Assistant hotel"]
    assert titles.(%{actor: :mcp}) == ["Claude hotel", "Cursor hotel"]
    assert titles.(%{actor: :mcp, client: "Cursor"}) == ["Cursor hotel"]
    assert titles.(%{client: "Claude Code"}) == ["Claude hotel"]
    assert titles.(%{actor: :task}) == ["By hand, scheduled"]
    assert titles.(%{actor: :person}) == ["Assistant", "By hand", "Claude", "Cursor"]
    assert Activity.count(%{actor: :mcp}) == 2
    assert Activity.clients() == ["Claude Code", "Cursor"]

    # The approver comes with the event
    assert [%Event{approver: %{id: approver_id}}] = Activity.list(%{actor: :assistant})
    assert approver_id == user.id
  end
end
