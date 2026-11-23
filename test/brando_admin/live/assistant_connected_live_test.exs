defmodule BrandoAdmin.AssistantConnectedLiveTest do
  # "From connected tools" follows the person's proposals as connected tools
  # store and change them, and as they are applied or discarded elsewhere,
  # while the proposal under review stays as it was read.
  use Brando.LiveCase

  import Brando.MCPHelpers
  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.Record
  alias Brando.MCP
  alias Brando.MCP.Grant
  alias Brando.MCP.Watch
  alias Brando.Pages.Page

  setup %{conn: conn, current_user: user} do
    setup_fetcher()
    enable_two_factor(user)
    tenant = MCP.tenant(nil, nil) |> switch!()
    tokens = connect!(conn, tenant)
    c = Brando.ProposalFixtures.context()
    Enum.each([c.identity, c.naming], &Brando.Content.create_identifier(Page, &1))
    %{tenant: tenant, token: token(tokens), grant: Repo.one!(Grant), identity: c.identity, naming: c.naming}
  end

  defp token(tokens), do: tokens["access_token"]

  # A retitle of the identity page, or of `arguments`' "entry"
  defp prepare(%{tenant: tenant, token: token} = c, title, arguments \\ %{}) do
    {entry, arguments} = Map.pop(arguments, "entry", c.identity)

    op = %{
      "op" => "set_fields",
      "target" => %{"content_type" => "Brando.Pages.Page", "id" => entry.id},
      "fields" => %{"title" => title}
    }

    %{"result" => %{"structuredContent" => %{"proposal_id" => id}}} =
      call_tool(tenant, token, "prepare_proposal", Map.merge(%{"summary" => title, "operations" => [op]}, arguments))

    id
  end

  defp row(id), do: ~s(#assistant-connected-list a[data-proposal-id="#{id}"])

  defp apply!(id, user) do
    {:ok, _} = Proposals.approve(id, 1, user)
    {:ok, _} = Proposals.apply(id, 1, user)
  end

  # The proposal's deadline, `ms` from now, set before the page opens
  defp expires_in(id, ms) do
    at = DateTime.add(DateTime.utc_now(), ms, :millisecond)
    Repo.update_all(from(r in Record, where: r.id == ^id), set: [expires_at: at])
    at
  end

  # Waits, without reading the page, until `at` has passed
  defp pass(at), do: Process.sleep(max(DateTime.diff(at, DateTime.utc_now(), :millisecond), 0) + 100)

  test "a stored proposal appears in the open list, with the count and its live page", %{conn: conn} = c do
    {:ok, chat, _} = live(conn, "/admin/assistant")
    refute has_element?(chat, ".assistant-connected-link")
    {:ok, view, _} = live(conn, "/admin/assistant/connected")
    assert has_element?(view, ".assistant-connected-empty")

    id = prepare(c, "Retitle the page")

    assert has_element?(view, row(id), "Retitle the page")
    assert has_element?(view, row(id) <> " [data-testid=assistant-state-waiting]")
    assert has_element?(view, ~s([data-testid=assistant-connected-live][href="#{Watch.path(c.grant)}"]))

    # And the count beside the link, on a conversation's page
    assert has_element?(chat, ".assistant-connected-link .assistant-count", "1")
  end

  test "a proposal from a connection made after the page opened appears", %{conn: conn, current_user: user} = c do
    {:ok, view, _} = live(conn, "/admin/assistant/connected")
    assert has_element?(view, ".assistant-connected-empty")

    # The tool signs in again: a new connection the page has never read
    tokens = connect_directly(user, c.tenant)
    id = prepare(%{c | token: token(tokens)}, "From a new connection")

    assert has_element?(view, row(id), "From a new connection")
  end

  test "a change is told once it is committed", %{current_user: user} = c do
    id = prepare(c, "Cancelled in a transaction")
    :ok = Proposals.subscribe(user)

    {:ok, _} =
      Brando.Repo.transaction(fn ->
        :ok = Proposals.cancel(id, user)
        refute_received {Proposals, :changed, ^id}
      end)

    assert_received {Proposals, :changed, ^id}
  end

  test "Follow live finds a client whose name is stored shortened", %{conn: conn} = c do
    # A name the proposal stores on one line, trimmed and cut to 80 characters
    name = "  My   Tool\n" <> String.duplicate("x", 100)
    Repo.update_all(from(g in Grant, where: g.id == ^c.grant.id), set: [client_name: name])

    id = prepare(c, "From a long name")
    assert Repo.get!(Record, id).client != name
    {:ok, view, _} = live(conn, "/admin/assistant/connected")

    assert has_element?(view, row(id))
    assert has_element?(view, ~s([data-testid=assistant-connected-live][href="#{Watch.path(c.grant)}"]))
  end

  test "each status change shows without a reload", %{conn: conn, current_user: user} = c do
    applied = prepare(c, "Applied one")
    {:ok, view, _} = live(conn, "/admin/assistant/connected")

    apply!(applied, user)
    assert has_element?(view, row(applied) <> " [data-testid=assistant-state-applied]")

    {:ok, _} = Proposals.undo(applied, user)
    assert has_element?(view, row(applied) <> " [data-testid=assistant-state-undone]")

    # Cancelled by the tool
    cancelled = prepare(c, "Cancelled one")
    assert has_element?(view, row(cancelled))
    call_tool(c.tenant, c.token, "cancel_proposal", %{"proposal_id" => cancelled})
    refute has_element?(view, row(cancelled))

    # Superseded by a newer version
    first = prepare(c, "First version")
    second = prepare(c, "Second version", %{"replaces" => first})
    refute has_element?(view, row(first))
    assert has_element?(view, row(second), "Second version")

    # Expired: with time, not a write
    Repo.update_all(from(r in Record, where: r.id == ^second), set: [expires_at: DateTime.add(DateTime.utc_now(), -1)])
    send(view.pid, {BrandoAdmin.AI.AssistantLive, :expiry})
    assert has_element?(view, row(second) <> " [data-testid=assistant-state-expired]")
  end

  test "the open proposal is not replaced by a newer version until the person asks", %{conn: conn} = c do
    first = prepare(c, "First version")
    {:ok, view, _} = live(conn, "/admin/assistant/connected/#{first}")
    assert has_element?(view, ".assistant-apply")

    second = prepare(c, "Second version", %{"replaces" => first})

    assert has_element?(view, row(second))
    assert has_element?(view, "#proposal-#{first}")
    assert has_element?(view, "#assistant-stale[data-reason=superseded]", "A newer version")
    assert has_element?(view, ".assistant-proposal-head h2", "Replaced by a newer version")
    refute has_element?(view, ".assistant-apply")
    refute has_element?(view, ~s(button[phx-click="cancel_proposal"]))

    view |> element("#assistant-stale a", "Show it") |> render_click()
    assert_patch(view, "/admin/assistant/connected/#{second}")
    assert has_element?(view, "#proposal-#{second}")
    refute has_element?(view, "#assistant-stale")
    assert has_element?(view, ".assistant-apply")
  end

  test "Approve is withdrawn when the proposal was applied elsewhere", %{conn: conn, current_user: user} = c do
    id = prepare(c, "Applied in another tab")
    {:ok, view, _} = live(conn, "/admin/assistant/connected/#{id}")
    assert has_element?(view, ".assistant-apply")

    apply!(id, user)

    assert has_element?(view, "#assistant-stale[data-reason=applied]", "applied elsewhere")
    assert has_element?(view, ".assistant-proposal-head h2", "Applied")
    refute has_element?(view, ".assistant-apply")
    # Still the version that was read: not swapped for its receipt
    refute has_element?(view, ".assistant-receipt")
  end

  test "the tool cancelling or the proposal expiring withdraws Approve", %{conn: conn} = c do
    id = prepare(c, "Cancelled by the tool")
    {:ok, view, _} = live(conn, "/admin/assistant/connected/#{id}")

    call_tool(c.tenant, c.token, "cancel_proposal", %{"proposal_id" => id})
    assert has_element?(view, "#assistant-stale[data-reason=cancelled]")
    refute has_element?(view, ".assistant-apply")

    other = prepare(c, "Expires")
    {:ok, view, _} = live(conn, "/admin/assistant/connected/#{other}")
    Repo.update_all(from(r in Record, where: r.id == ^other), set: [expires_at: DateTime.add(DateTime.utc_now(), -1)])
    send(view.pid, {BrandoAdmin.AI.AssistantLive, :expiry})
    assert has_element?(view, "#assistant-stale[data-reason=expired]")
    refute has_element?(view, ".assistant-apply")
  end

  test "a row stops waiting for review when its deadline passes", %{conn: conn} = c do
    id = prepare(c, "Expires while open")
    at = expires_in(id, 800)
    {:ok, view, _} = live(conn, "/admin/assistant/connected/#{id}")
    assert has_element?(view, row(id) <> " [data-testid=assistant-state-waiting]")

    pass(at)

    assert has_element?(view, "#assistant-stale[data-reason=expired]")
    assert has_element?(view, row(id) <> " [data-testid=assistant-state-expired]")
  end

  test "a proposal under review expires on time when it is not among the listed rows",
       %{conn: conn, current_user: user} = c do
    id = prepare(c, "Older than the list")
    at = expires_in(id, 800)
    pending = Repo.get!(Record, id)

    # Newer, finished ones fill the list
    for n <- 1..30 do
      Repo.insert!(%{
        pending
        | id: Ecto.UUID.generate(),
          status: "applied",
          summary: "Applied #{n}",
          inserted_at: DateTime.add(pending.inserted_at, n, :second)
      })
    end

    {:ok, chat, _} = live(conn, "/admin/assistant")
    {:ok, view, _} = live(conn, "/admin/assistant/connected/#{id}")
    refute has_element?(view, row(id))
    assert has_element?(chat, ".assistant-connected-link .assistant-count", "1")
    assert has_element?(view, ".assistant-apply")
    assert Proposals.count_external(user) == 1

    pass(at)

    refute has_element?(chat, ".assistant-connected-link .assistant-count")
    assert has_element?(view, "#assistant-stale[data-reason=expired]")
    refute has_element?(view, ".assistant-apply")
  end

  test "an approve of a version superseded since is refused", %{conn: conn} = c do
    first = prepare(c, "First version")
    {:ok, view, _} = live(conn, "/admin/assistant/connected/#{first}")

    # The click left before the newer version's event arrived
    second = prepare(c, "Second version", %{"replaces" => first})
    render_click(view, "apply", %{"id" => first, "version" => "1"})

    assert has_element?(view, "[role=alert]", "A newer version of this proposal exists")
    assert Repo.get!(Record, first).status == "superseded"
    assert Repo.get!(Record, second).status == "pending"
    assert Repo.get!(Page, c.identity.id).title != "First version"
  end

  @tag :capture_log
  test "an open preview stays open as the list changes", %{conn: conn} = c do
    id = prepare(c, "Previewed")
    {:ok, view, _} = live(conn, "/admin/assistant/connected/#{id}?preview")
    assert has_element?(view, ".assistant-preview")

    other = prepare(c, "About another entry", %{"entry" => c.naming})
    assert has_element?(view, row(other))
    assert has_element?(view, ".assistant-preview")
  end

  @tag :capture_log
  test "an open preview withdraws Share a link once the proposal is stale", %{conn: conn} = c do
    id = prepare(c, "Previewed")
    {:ok, view, _} = live(conn, "/admin/assistant/connected/#{id}?preview")
    view |> element(~s(button[phx-value-target="blocks"])) |> render_click()
    assert has_element?(view, ~s(button[phx-click="share_page"]))

    call_tool(c.tenant, c.token, "cancel_proposal", %{"proposal_id" => id})

    assert has_element?(view, "#assistant-stale[data-reason=cancelled]")
    refute has_element?(view, ~s(button[phx-click="share_page"]))
  end

  test "another person's or another site's proposal never appears", %{conn: conn, current_user: user} = c do
    {:ok, view, _} = live(conn, "/admin/assistant/connected")

    # Another person's connection to the same site
    someone = Factory.insert(:random_user, role: :admin, config: %Brando.Users.UserConfig{}) |> enable_two_factor()
    tokens = connect_directly(someone, c.tenant)
    theirs = prepare(%{c | token: token(tokens)}, "Theirs")

    # The person's own proposal in another site environment
    elsewhere =
      Repo.insert!(%Record{
        id: Ecto.UUID.generate(),
        version: 1,
        scope: "site:elsewhere",
        actor_id: user.id,
        summary: "Elsewhere",
        origin: "mcp",
        client: c.grant.client_name,
        operations: [],
        fingerprints: %{},
        module_versions: [],
        problems: [],
        effects: %{},
        expires_at: DateTime.add(DateTime.utc_now(), 3_600, :second)
      })

    # Even told of them, the page reads the list as it opens it
    send(view.pid, {Proposals, :changed, elsewhere.id})

    refute has_element?(view, row(theirs))
    refute has_element?(view, row(elsewhere.id))
    assert has_element?(view, ".assistant-connected-empty")
  end
end
