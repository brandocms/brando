defmodule BrandoAdmin.MCP.MCPLiveTest do
  # The admin side of connected AI tools: the switch and everyone's
  # connections under Configuration, the person's own Connected apps on the
  # security page, and what Activity shows.
  use Brando.LiveCase

  import Brando.MCPHelpers
  import Ecto.Query, only: [from: 2]

  alias Brando.MCP
  alias Brando.MCP.Grant
  alias Brando.MCP.Setting

  setup %{current_user: user} do
    setup_fetcher()
    enable_two_factor(user)
    %{tenant: MCP.tenant(nil, nil)}
  end

  describe "Configuration → Connected AI tools" do
    test "is off at first, and turning it on and off is recorded", %{conn: conn, tenant: tenant, current_user: user} do
      {:ok, view, html} = live(conn, "/admin/config/mcp")
      assert html =~ ~s(data-enabled="false")
      refute MCP.enabled?(tenant)

      view |> element("[data-testid=mcp-enable]") |> render_click()
      assert MCP.enabled?(tenant)
      assert render(view) =~ MCP.resource(tenant)
      assert %Setting{enabled: true, changed_by_id: user_id} = Repo.one!(Setting)
      assert user_id == user.id

      view |> element("[data-testid=mcp-disable]") |> render_click()
      refute MCP.enabled?(tenant)

      details =
        Repo.all(
          from e in Brando.Activity.Event,
            where: e.schema == "Elixir.Brando.MCP.Setting",
            order_by: e.id,
            select: e.details
        )

      assert [%{"mcp" => "enabled"}, %{"mcp" => "disabled"}] = details
    end

    test "asks to confirm before turning it on when the session has not lately", %{conn: conn, tenant: tenant} do
      token = get_session(conn, :user_token)
      hour_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -3600, :second)
      Repo.update_all(from(t in Brando.Users.UserToken, where: t.token == ^token), set: [confirmed_at: hour_ago])

      {:ok, view, _html} = live(conn, "/admin/config/mcp")
      assert view |> element("[data-testid=mcp-enable]") |> render_click() =~ "reauth-modal"
      refute MCP.enabled?(tenant)
    end

    test "lists everyone's connections and revokes one", %{conn: conn, tenant: tenant} do
      switch!(tenant)
      tokens = connect!(conn, tenant)

      {:ok, view, html} = live(conn, "/admin/config/mcp")
      assert html =~ "Test Client"
      grant = Repo.one!(Grant)

      view |> element("[data-testid=mcp-grant-revoke][phx-value-id='#{grant.id}']") |> render_click()
      assert %Grant{revoked_reason: "admin"} = Repo.one!(Grant)
      refute render(view) =~ ~s(data-testid="mcp-grant")
      assert rpc(tenant, tokens["access_token"], "ping").status == 401
    end

    test "is for those who may manage connections", %{tenant: tenant} do
      editor = Brando.Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
      conn = log_in_user(build_conn(), editor)
      assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(conn, "/admin/config/mcp")
      refute MCP.can_manage?(editor, tenant)
    end

    test "Integrations links to it", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin/config/integrations")
      assert html =~ ~s(data-testid="integration-mcp")
      assert html =~ "/admin/config/mcp"
    end
  end

  describe "Security → Connected apps" do
    test "lists the person's connections and disconnects one", %{conn: conn, tenant: tenant, current_user: user} do
      switch!(tenant)
      tokens = connect!(conn, tenant)

      {:ok, view, html} = live(conn, "/admin/users/security")
      assert html =~ ~s(data-testid="connected-apps")
      assert html =~ "Test Client"
      grant = Repo.one!(Grant)

      view |> element("[data-testid=connected-app-revoke]") |> render_click()
      assert %Grant{revoked_reason: "user", revoked_by_id: by} = Repo.one!(Grant)
      assert by == user.id
      refute render(view) =~ ~s(data-testid="connected-app")
      assert rpc(tenant, tokens["access_token"], "ping").status == 401

      # The security log says so.
      {:ok, _view, html} = live(conn, "/admin/users/security")
      assert html =~ "Disconnected Test Client"
      assert grant
    end

    test "a person cannot revoke someone else's connection", %{conn: conn, tenant: tenant} do
      switch!(tenant)
      connect!(conn, tenant)
      grant = Repo.one!(Grant)
      other = Brando.Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
      assert {:error, :not_found} = MCP.revoke(grant.id, other)
      assert %Grant{revoked_at: nil} = Repo.one!(Grant)
    end
  end

  describe "Activity" do
    test "shows connections and tool calls with the client and the person", %{conn: conn, tenant: tenant} do
      switch!(tenant)
      tokens = connect!(conn, tenant)
      call_tool(tenant, tokens["access_token"], "list_content_types")

      {:ok, _view, html} = live(conn, "/admin/config/activity")
      assert html =~ "Test Client via MCP"
      assert html =~ "list_content_types"
      assert html =~ "Connected over MCP"
    end
  end
end
