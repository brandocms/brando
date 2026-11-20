defmodule BrandoAdmin.MCP.WatchLiveTest do
  # The live page of a connected tool: who may open it, what it opens on,
  # and calls over the endpoint appearing on it as they happen.
  use Brando.LiveCase

  import Brando.MCPHelpers

  alias Brando.Authorization.{Boundary, Groups, Migration, Scope}
  alias Brando.Content.Proposals.Record
  alias Brando.MCP
  alias Brando.MCP.Grant
  alias Brando.MCP.Watch
  alias Brando.Pages.Page
  alias Brando.Tenant
  alias Brando.Tenant.{Access, Cache, Registry}

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

  defp proposal!(user, attrs \\ %{}) do
    Repo.insert!(
      struct(
        %Record{
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
        },
        attrs
      )
    )
  end

  defp proposal_details(record),
    do: %{"tool" => "prepare_proposal", "ok" => true, "output" => %{"version" => 2}, "proposal" => record.id}

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

    test "a proposal replacing an image's file counts it, and says so on its line",
         %{conn: conn, tenant: tenant, token: token, grant: grant} do
      old = Brando.ImageFileFixtures.file_image("old", {800, 600})
      new = Brando.ImageFileFixtures.file_image("new", {1600, 1200})
      {:ok, view, _html} = page(conn, grant)

      op = %{
        "op" => "replace_image_file",
        "asset" => %{"kind" => "image", "id" => old.id},
        "with" => %{"kind" => "image", "id" => new.id}
      }

      %{"result" => %{"structuredContent" => %{"proposal_id" => id}}} =
        call_tool(tenant, token, "prepare_proposal", %{"summary" => "Better photo", "operations" => [op]})

      card = "[data-proposal-id='#{id}']"
      assert has_element?(view, card <> " h3", "Better photo")
      # The version, and the one replaced file
      assert [_version, _replaced] =
               view |> element(card <> " .mcp-watch-counts") |> render() |> String.split(" · ")
    end

    test "a proposal with problems lists them", %{conn: conn, grant: grant, current_user: user} do
      record = proposal!(user)

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
        "folder" => "figma/case-tipping",
        "images" => [%{"id" => first.id, "reused" => false}, %{"id" => second.id, "reused" => true}],
        "failed" => 1
      }

      Watch.finished(grant.id, "import", details, {:error, :not_recorded})

      row = "#mcp-call-import"
      assert has_element?(view, row, "Imported 2 images from “Case – Tipping”")
      assert has_element?(view, row <> " .mcp-watch-folder", "figma/case-tipping")
      assert has_element?(view, row <> " [data-image-id='#{first.id}'][data-reused=false]", "New")
      assert has_element?(view, row <> " [data-image-id='#{second.id}'][data-reused=true]", "Reused")
      assert has_element?(view, row <> " [data-image-id='#{first.id}'] img")
      assert has_element?(view, row <> " .mcp-watch-error", "1 image could not be imported.")
    end

    test "an upload and an import from an address, with their image and folder", %{conn: conn, grant: grant} do
      [uploaded, imported] = for _ <- 1..2, do: Factory.insert(:image)
      {:ok, view, _html} = page(conn, grant)
      finish = &Watch.finished(grant.id, &1, Map.put(&2, "ok", true), {:error, :not_recorded})

      finish.("prepare", %{
        "tool" => "brando_media_prepare_upload",
        "input" => %{"kind" => "image", "filename" => "harbour.jpg"}
      })

      finish.("upload", %{
        "tool" => "brando_media_finish_upload",
        "output" => %{"images" => 1, "reused" => false},
        "folder" => "uploads",
        "images" => [%{"id" => uploaded.id, "reused" => false}]
      })

      finish.("import", %{
        "tool" => "brando_media_import_url",
        "output" => %{"images" => 1, "reused" => true},
        "folder" => "uploads",
        "images" => [%{"id" => imported.id, "reused" => true}]
      })

      assert has_element?(view, "#mcp-call-prepare", "Prepared to upload “harbour.jpg”")
      assert has_element?(view, "#mcp-call-upload", "Uploaded an image to the media library")
      assert has_element?(view, "#mcp-call-upload .mcp-watch-folder", "uploads")
      assert has_element?(view, "#mcp-call-upload [data-image-id='#{uploaded.id}'][data-reused=false]")
      assert has_element?(view, "#mcp-call-import", "Imported an image the media library already had")
      assert has_element?(view, "#mcp-call-import [data-image-id='#{imported.id}'][data-reused=true]")
    end

    test "an approved proposal says so", %{conn: conn, grant: grant, current_user: user} do
      record = proposal!(user, %{status: "approved", problems: [], approved_at: DateTime.utc_now()})
      {:ok, view, _html} = page(conn, grant)

      Watch.finished(grant.id, "approved", proposal_details(record), {:error, :not_recorded})
      assert has_element?(view, "#mcp-call-approved [data-proposal-id='#{record.id}'] .badge", "Approved")
    end

    test "an image moved to the trash shows no thumbnail", %{conn: conn, grant: grant} do
      image = Factory.insert(:image, deleted_at: DateTime.utc_now())
      {:ok, view, _html} = page(conn, grant)

      details = %{
        "tool" => "brando_figma_import_images",
        "ok" => true,
        "images" => [%{"id" => image.id, "reused" => false}]
      }

      Watch.finished(grant.id, "trashed", details, {:error, :not_recorded})
      assert has_element?(view, "#mcp-call-trashed [data-image-id='#{image.id}']")
      refute has_element?(view, "#mcp-call-trashed [data-image-id='#{image.id}'] img")
    end

    test "a call that ended before the history was read shows once, as ended",
         %{conn: conn, tenant: tenant, token: token, grant: grant} do
      call_tool(tenant, token, "list_content_types")
      [event] = Watch.history(grant)
      {:ok, view, _html} = page(conn, grant)

      # Its start, then its end, arrive after the history was read
      Watch.started(grant.id, "raced", "brando_content_list_content_types", %{})
      Watch.finished(grant.id, "raced", event.details, {:ok, Repo.get!(Brando.Activity.Event, event.event_id)})

      refute has_element?(view, "#mcp-call-raced")
      assert has_element?(view, "#mcp-call-event-#{event.event_id}[data-state=ok]")
    end
  end

  describe "when the connection expires" do
    test "an open page says it ended", %{conn: conn, grant: grant} do
      # Made long enough ago that it expires in a moment
      inserted_at = DateTime.add(DateTime.utc_now(), 200 - MCP.grant_days() * 86_400_000, :millisecond)
      grant = grant |> Ecto.Changeset.change(inserted_at: inserted_at) |> Repo.update!()

      {:ok, view, _html} = page(conn, grant)
      assert has_element?(view, "[data-testid=mcp-watch][data-live=true]")
      await_selector(view, "[data-testid=mcp-watch][data-live=false]")
      assert has_element?(view, "[data-testid=mcp-watch-status]", "Disconnected")
    end
  end

  describe "the connection's own person" do
    test "may not open it once deactivated", %{conn: conn, grant: grant, current_user: user} do
      user |> Ecto.Changeset.change(active: false) |> Repo.update!()
      assert {:error, {:redirect, %{to: "/admin/login"}}} = page(conn, grant)
    end
  end

  describe "with group authorization" do
    setup c do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :none)
      Boundary.put_scope(nil)
      scope = Scope.standalone(user(:superuser))
      {:ok, _} = Migration.run()
      owner = user(:user)
      {:ok, group} = Groups.create(scope, %{name: "Connect"}, ["brando.admin.access", "brando.mcp.connect"])
      {:ok, :ok} = Groups.add_member(scope, group.id, owner.id)
      connect_directly(owner, c.tenant)
      %{owner: owner, owner_grant: Repo.get_by!(Grant, user_id: owner.id), scope: scope}
    end

    defp member(c, keys) do
      user = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
      {:ok, group} = Groups.create(c.scope, %{name: "Group #{System.unique_integer([:positive])}"}, keys)
      {:ok, :ok} = Groups.add_member(c.scope, group.id, user.id)
      {user, group, log_in_user(admin_conn(), user)}
    end

    test "a manager who may not read the content sees the steps, not what they named", c do
      {_manager, _group, conn} = member(c, ["brando.admin.access", "brando.mcp.manage"])
      image = Factory.insert(:image)
      page_entry = Factory.insert(:page)

      record =
        proposal!(c.owner, %{
          summary: "Retitle the secret page",
          operations: [
            %{
              "op" => "set_fields",
              "target" => %{"content_type" => "Brando.Pages.Page", "id" => page_entry.id},
              "fields" => %{"title" => "Secret"}
            }
          ]
        })

      {:ok, view, _html} = page(conn, c.owner_grant)

      grant = c.owner_grant.id
      finish = &Watch.finished(grant, &1, Map.put(&2, "ok", true), {:error, :not_recorded})
      finish.("outline", %{"tool" => "brando_content_entry_outline", "output" => %{"title" => "Secret title"}})

      finish.("search", %{
        "tool" => "brando_content_search_entries",
        "input" => %{"query" => "secret words", "content_type" => "Brando.Pages.Page"}
      })

      finish.("import", %{
        "tool" => "brando_figma_import_images",
        "output" => %{"frame" => "Secret frame", "images" => 1},
        "folder" => "figma/secret-folder",
        "images" => [%{"id" => image.id, "reused" => false}]
      })

      finish.("proposal", proposal_details(record))
      finish.("prepare", %{"tool" => "brando_media_prepare_upload", "input" => %{"filename" => "Secret file.jpg"}})

      assert has_element?(view, "#mcp-call-prepare", "Prepared an upload")
      assert has_element?(view, "#mcp-call-outline", "Read an entry")
      assert has_element?(view, "#mcp-call-search", "Searched Pages")
      assert has_element?(view, "#mcp-call-import", "Imported images from a Figma frame")
      assert has_element?(view, "#mcp-call-import [data-image-id='#{image.id}']")
      refute has_element?(view, "#mcp-call-import img")
      refute has_element?(view, "#mcp-call-import .mcp-watch-folder")
      assert has_element?(view, "#mcp-call-proposal .mcp-watch-counts", "1 updated entry")
      assert has_element?(view, "#mcp-call-proposal .badge", "Needs changes")
      refute has_element?(view, "#mcp-call-proposal .mcp-watch-problems")

      html = render(view)
      for secret <- ["Secret", "secret words", "Retitle", "The title is required."], do: refute(html =~ secret)
    end

    test "a manager who may read it sees the proposal's summary and problems", c do
      {_manager, _group, conn} =
        member(c, ["brando.admin.access", "brando.mcp.manage", "brando.pages.read", "brando.images.read"])

      image = Factory.insert(:image)
      page_entry = Factory.insert(:page)

      record =
        proposal!(c.owner, %{
          summary: "Retitle the page",
          operations: [
            %{
              "op" => "set_fields",
              "target" => %{"content_type" => "Brando.Pages.Page", "id" => page_entry.id},
              "fields" => %{"title" => "Open"}
            }
          ]
        })

      {:ok, view, _html} = page(conn, c.owner_grant)
      Watch.finished(c.owner_grant.id, "proposal", proposal_details(record), {:error, :not_recorded})

      details = %{"tool" => "brando_figma_import_images", "ok" => true, "images" => [%{"id" => image.id}]}
      Watch.finished(c.owner_grant.id, "import", details, {:error, :not_recorded})

      assert has_element?(view, "#mcp-call-proposal h3", "Retitle the page")
      assert has_element?(view, "#mcp-call-proposal .mcp-watch-problems li", "The title is required.")
      assert has_element?(view, "#mcp-call-import [data-image-id='#{image.id}'] img")
    end

    test "an applied image replacement is read by OLD, NEW's record being gone", c do
      {_manager, _group, conn} = member(c, ["brando.admin.access", "brando.mcp.manage", "brando.images.read"])
      old = Factory.insert(:image)
      new = Factory.insert(:image)
      Repo.delete!(new)

      record =
        proposal!(c.owner, %{
          summary: "Swap the photo",
          status: "applied",
          problems: [],
          operations: [
            %{
              "op" => "replace_image_file",
              "asset" => %{"kind" => "image", "id" => old.id},
              "with" => %{"kind" => "image", "id" => new.id}
            }
          ]
        })

      {:ok, view, _html} = page(conn, c.owner_grant)
      Watch.finished(c.owner_grant.id, "proposal", proposal_details(record), {:error, :not_recorded})
      assert has_element?(view, "#mcp-call-proposal h3", "Swap the photo")
    end

    test "a manager who loses a read permission stays, with the calls read again", c do
      {:ok, manage} = Groups.create(c.scope, %{name: "Manage"}, ["brando.admin.access", "brando.mcp.manage"])
      {manager, read, conn} = member(c, ["brando.pages.read", "brando.images.read"])
      {:ok, :ok} = Groups.add_member(c.scope, manage.id, manager.id)

      page_entry = Factory.insert(:page)

      record =
        proposal!(c.owner, %{
          summary: "Retitle the page",
          operations: [
            %{
              "op" => "set_fields",
              "target" => %{"content_type" => "Brando.Pages.Page", "id" => page_entry.id},
              "fields" => %{"title" => "Open"}
            }
          ]
        })

      # In Activity, as a call the page was told of and wrote; and one still running
      event =
        Repo.insert!(%Brando.Activity.Event{
          action: :tool_called,
          source: :mcp,
          user_id: c.owner.id,
          schema: to_string(Grant),
          entry_id: c.owner_grant.id,
          details: proposal_details(record)
        })

      {:ok, view, _html} = page(conn, c.owner_grant)
      Watch.started(c.owner_grant.id, "running", "brando_content_search_entries", %{"query" => "secret words"})
      assert has_element?(view, "#mcp-call-event-#{event.id} h3", "Retitle the page")
      assert has_element?(view, "#mcp-call-running[data-state=running]")

      {:ok, :ok} = Groups.remove_member(c.scope, read.id, manager.id)

      # Still here, the proposal without its summary, the running call kept
      assert has_element?(view, "[data-testid=mcp-watch]")
      assert has_element?(view, "#mcp-call-event-#{event.id} .mcp-watch-counts", "1 updated entry")
      refute render(view) =~ "Retitle the page"
      assert has_element?(view, "#mcp-call-running[data-state=running]")
    end

    test "a manager who loses the permission is sent away", c do
      {manager, group, conn} = member(c, ["brando.admin.access", "brando.mcp.manage"])
      {:ok, view, _html} = page(conn, c.owner_grant)
      assert has_element?(view, "[data-testid=mcp-watch]")

      {:ok, :ok} = Groups.remove_member(c.scope, group.id, manager.id)
      assert_redirect(view, "/admin/access-denied")
    end
  end

  describe "with sites, legacy authorization" do
    setup do
      put_test_env(:authorization_mode, :legacy)
      put_test_env(:tenancy_mode, :multi)
      Cache.clear()
      Tenant.put_prefix(nil)

      on_exit(fn ->
        Cache.clear()
        Tenant.put_prefix(nil)
      end)

      here = site("watch-here")
      environment(here, "production")
      there = site("watch-there")
      there_production = environment(there, "production")
      Cache.warm()

      tenant = MCP.tenant(Cache.get_site(there.key), Cache.get_env(there.key, there_production.key)) |> switch!()
      owner = user(:editor)
      {:ok, _} = Access.grant(owner, there, :admin)
      connect_directly(owner, tenant)
      grant = Repo.get_by!(Grant, user_id: owner.id)

      viewer = user(:editor)
      {:ok, _} = Access.grant(viewer, here, :admin)
      {:ok, _} = Access.grant(viewer, there, :admin)

      conn = viewer_conn(viewer, here)
      %{here: here, there: there, owner: owner, viewer: viewer, viewer_conn: conn, site_grant: grant}
    end

    defp viewer_conn(user, site),
      do: admin_conn() |> log_in_user(user) |> Plug.Test.init_test_session(%{"brando_site_key" => site.key})

    test "a site admin who becomes an editor of the connection's site is sent away", c do
      {:ok, view, _html} = page(c.viewer_conn, c.site_grant)
      assert has_element?(view, "[data-testid=mcp-watch]")

      {:ok, _} = Access.grant(c.viewer, c.there, :editor)
      assert_redirect(view, "/admin/access-denied")
    end

    test "a viewer in another site is sent away when the connection's site is suspended", c do
      {:ok, view, _html} = page(c.viewer_conn, c.site_grant)
      assert has_element?(view, "[data-testid=mcp-watch]")

      {:ok, _} = Brando.Tenant.Setup.suspend_site(c.there)
      assert_redirect(view, "/admin/access-denied")
    end

    test "the person may not open it without access to the connection's site", c do
      :ok = Access.revoke(c.owner, c.there)
      {:ok, _} = Access.grant(c.owner, c.here, :admin)

      assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = page(viewer_conn(c.owner, c.here), c.site_grant)
    end
  end

  defp site(key) do
    {:ok, site} =
      Registry.create_site(%{
        name: key,
        key: key,
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    site
  end

  # An environment schema with a copy of every tenant table, inside the
  # test's transaction
  defp environment(site, key) do
    {:ok, environment} = Registry.create_environment(site, %{name: key, key: key, live: true})
    prefix = Tenant.prefix(site, environment)
    Repo.query!(~s(CREATE SCHEMA "#{prefix}"))

    "SELECT tablename FROM pg_tables WHERE schemaname = 'public'"
    |> Repo.query!()
    |> Map.fetch!(:rows)
    |> List.flatten()
    |> Enum.reject(&Tenant.SharedTables.member?/1)
    |> Enum.each(fn table ->
      escaped = String.replace(table, "\"", "\"\"")
      Repo.query!(~s|CREATE TABLE "#{prefix}"."#{escaped}" (LIKE public."#{escaped}" INCLUDING ALL)|)
    end)

    environment
  end
end
