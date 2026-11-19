defmodule BrandoAdmin.MCP.WatchLiveTest do
  # The live page of a connected tool: who may open it, what it opens on,
  # and calls over the endpoint appearing on it as they happen.
  use Brando.LiveCase

  import Brando.MCPHelpers

  alias Brando.MCP
  alias Brando.MCP.Grant
  alias Brando.MCP.Watch
  alias Brando.Pages.Page

  setup %{conn: conn, current_user: user} do
    setup_fetcher()
    enable_two_factor(user)
    tenant = MCP.tenant(nil, nil) |> switch!()
    tokens = connect!(conn, tenant)
    %{tenant: tenant, token: tokens["access_token"], grant: Repo.one!(Grant)}
  end

  defp user(role) do
    Factory.insert(:random_user, role: role, config: %Brando.Users.UserConfig{}) |> enable_two_factor()
  end

  defp page(conn, grant), do: live(conn, Watch.path(grant))

  describe "who may open it" do
    test "the connection's person", %{conn: conn, grant: grant} do
      assert {:ok, view, _html} = page(conn, grant)
      assert has_element?(view, "[data-testid=mcp-watch][data-live=true]")
      assert has_element?(view, "h1", "Test Client")
      assert has_element?(view, "[data-testid=mcp-watch-empty]", "Waiting for the tool…")
      assert has_element?(view, ~s(a[href="/admin/assistant/connected"]))
    end

    test "someone who manages connected tools, for another person's connection", %{tenant: tenant} do
      owner = user(:admin)
      tokens = connect_directly(owner, tenant)
      grant = Repo.get_by!(Grant, user_id: owner.id)
      manager = user(:admin)

      assert {:ok, view, _html} = page(log_in_user(admin_conn(), manager), grant)
      assert render(view) =~ owner.name
      # Their proposals are the person's, reviewed by the person
      refute has_element?(view, ~s(a[href="/admin/assistant/connected"]))

      call_tool(tenant, tokens["access_token"], "list_content_types")
      assert has_element?(view, "[data-tool=list_content_types][data-state=ok]")

      # The person's proposal shows, without the review only they can open
      c = Brando.ProposalFixtures.context()
      Brando.Content.create_identifier(Page, c.identity)

      op = %{
        "op" => "set_fields",
        "target" => %{"content_type" => "Brando.Pages.Page", "id" => c.identity.id},
        "fields" => %{"title" => "Theirs"}
      }

      call_tool(tenant, tokens["access_token"], "prepare_proposal", %{"summary" => "Theirs", "operations" => [op]})
      assert has_element?(view, ".mcp-watch-proposal h3", "Theirs")
      refute has_element?(view, ".mcp-watch-proposal a")
    end

    test "is linked from Connected apps and from the connections under Configuration",
         %{conn: conn, grant: grant} do
      path = Watch.path(grant)
      {:ok, security, _html} = live(conn, "/admin/users/security")
      assert has_element?(security, ~s([data-testid=connected-app-watch][href="#{path}"]))

      {:ok, settings, _html} = live(conn, "/admin/config/mcp")
      assert has_element?(settings, ~s([data-testid=mcp-grant-watch][href="#{path}"]))
    end

    test "nobody else, even with the link", %{grant: grant} do
      editor = user(:editor)

      assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = page(log_in_user(admin_conn(), editor), grant)
    end

    test "nothing for a connection that does not exist", %{conn: conn, grant: grant} do
      assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(conn, Watch.path(grant.id + 1_000))
      assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(conn, "/admin/assistant/connected/live/x")
    end

    test "a revoked connection shows what it did and that it ended", %{conn: conn, tenant: tenant, token: token} = c do
      call_tool(tenant, token, "list_content_types")
      :ok = MCP.revoke(c.grant.id, c.current_user)

      {:ok, view, _html} = page(conn, c.grant)
      assert has_element?(view, "[data-testid=mcp-watch][data-live=false]")
      assert has_element?(view, "[data-testid=mcp-watch-status]", "Disconnected")
      assert has_element?(view, "[data-tool=list_content_types]")
    end

    test "revoking it while the page is open says it ended", %{conn: conn, grant: grant} = c do
      {:ok, view, _html} = page(conn, grant)
      :ok = MCP.revoke(grant.id, c.current_user)
      assert has_element?(view, "[data-testid=mcp-watch-status]", "Disconnected")
      assert has_element?(view, "[data-testid=mcp-watch-empty]", "No calls in the last hour")
    end
  end

  describe "what it shows" do
    test "opens on the connection's calls of the last hour, newest first",
         %{conn: conn, tenant: tenant, token: token, grant: grant} do
      call_tool(tenant, token, "list_content_types")
      call_tool(tenant, token, "search_assets", %{"kind" => "image", "query" => "hero"})
      call_tool(tenant, token, "describe_module", %{"module" => "local:0"})

      {:ok, view, _html} = page(conn, grant)
      refute has_element?(view, "[data-testid=mcp-watch-empty]")

      rows = view |> render() |> Floki.parse_document!() |> Floki.find(".mcp-watch-call")

      assert Enum.map(rows, &Floki.attribute(&1, "data-tool")) == [
               ["describe_module"],
               ["search_assets"],
               ["list_content_types"]
             ]

      assert has_element?(view, "[data-tool=search_assets] .mcp-watch-label", "Searched the media library for “hero”")
      assert has_element?(view, "[data-tool=describe_module][data-state=error] [data-testid=mcp-watch-state]", "Failed")
      assert has_element?(view, "[data-tool=describe_module] .mcp-watch-error")
    end

    test "shows a call as it starts and as it ends", %{conn: conn, tenant: tenant, token: token, grant: grant} do
      {:ok, view, _html} = page(conn, grant)

      # As the endpoint would tell it, before the call ends
      Watch.started(grant.id, "running-call", "search_entries", %{"query" => "Identity"})
      assert has_element?(view, "#mcp-call-running-call[data-state=running]", "Searched for “Identity”")
      refute has_element?(view, "[data-testid=mcp-watch-empty]")

      call_tool(tenant, token, "search_entries", %{"query" => "Ident", "content_type" => "Brando.Pages.Page"})
      assert has_element?(view, "[data-tool=search_entries][data-state=ok]", "Searched for “Ident” in Pages")
    end

    test "a proposal with its summary, counts and links", %{conn: conn, tenant: tenant, token: token, grant: grant} do
      c = Brando.ProposalFixtures.context()
      Enum.each([c.identity, c.naming], &Brando.Content.create_identifier(Page, &1))
      {:ok, view, _html} = page(conn, grant)

      op = %{
        "op" => "set_fields",
        "target" => %{"content_type" => "Brando.Pages.Page", "id" => c.identity.id},
        "fields" => %{"title" => "Identity, from MCP"}
      }

      %{"result" => %{"structuredContent" => %{"proposal_id" => id}}} =
        call_tool(tenant, token, "prepare_proposal", %{"summary" => "Retitle the page", "operations" => [op]})

      card = "[data-proposal-id='#{id}']"
      assert has_element?(view, card <> " h3", "Retitle the page")
      assert has_element?(view, card <> " .mcp-watch-counts", "1 updated entry")
      assert has_element?(view, card <> " .badge", "Waiting for review")
      assert has_element?(view, card <> ~s( a[href="/admin/assistant/connected/#{id}"]))

      assert has_element?(
               view,
               card <> ~s( a[href="/admin/assistant/connected/#{id}?preview=Brando.Pages.Page:#{c.identity.id}"])
             )

      # And from Activity, when the page opens later
      {:ok, view, _html} = page(conn, grant)
      assert has_element?(view, card <> " h3", "Retitle the page")
    end

    test "a proposal with problems lists them", %{conn: conn, grant: grant, current_user: user} do
      record =
        Repo.insert!(%Brando.Content.Proposals.Record{
          id: Ecto.UUID.generate(),
          version: 2,
          scope: "standalone",
          actor_id: user.id,
          summary: "Clear the title",
          origin: "mcp",
          operations: [],
          fingerprints: %{},
          module_versions: [],
          problems: [%{"code" => "required", "message" => "The title is required."}],
          effects: %{"updates" => 1, "deletions" => 0},
          expires_at: DateTime.add(DateTime.utc_now(), 3_600, :second)
        })

      {:ok, view, _html} = page(conn, grant)

      details = %{
        "tool" => "prepare_proposal",
        "ok" => true,
        "output" => %{"version" => 2, "applicable" => false},
        "proposal" => record.id
      }

      Watch.finished(grant.id, "with-problems", details, {:error, :not_recorded})

      card = "#mcp-call-with-problems [data-proposal-id='#{record.id}']"
      assert has_element?(view, "#mcp-call-with-problems", "Prepared version 2, with problems to fix")
      assert has_element?(view, card <> " .mcp-watch-problems li", "The title is required.")
      assert has_element?(view, card <> " .badge", "Needs changes")
      refute has_element?(view, card <> " a", "Open on the page")
    end

    test "imported images with their folder, new and reused", %{conn: conn, grant: grant} do
      [first, second] = for _ <- 1..2, do: Factory.insert(:image)
      {:ok, view, _html} = page(conn, grant)

      details = %{
        "tool" => "brando_figma_import_images",
        "ok" => true,
        "output" => %{"frame" => "Case – Tipping", "images" => 2},
        "folder" => "Figma/Case – Tipping",
        "images" => [%{"id" => first.id, "reused" => false}, %{"id" => second.id, "reused" => true}],
        "failed" => 1
      }

      Watch.finished(grant.id, "import", details, {:error, :not_recorded})

      row = "#mcp-call-import"
      assert has_element?(view, row, "Imported 2 images from “Case – Tipping”")
      assert has_element?(view, row <> " .mcp-watch-folder", "Figma/Case – Tipping")
      assert has_element?(view, row <> " [data-image-id='#{first.id}'][data-reused=false]", "New")
      assert has_element?(view, row <> " [data-image-id='#{second.id}'][data-reused=true]", "Reused")
      assert has_element?(view, row <> " [data-image-id='#{first.id}'] img")
      assert has_element?(view, row <> " .mcp-watch-error", "1 image could not be imported.")
    end
  end
end
