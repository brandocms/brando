defmodule BrandoAdmin.MCP.MCPLiveTest do
  # The admin side of connected AI tools: the switch and everyone's
  # connections under Configuration, the person's own Connected apps on the
  # security page, and what Activity shows.
  use Brando.LiveCase

  import Brando.MCPHelpers
  import Brando.Test.Support, only: [put_test_env: 2]
  import Ecto.Query, only: [from: 2]

  alias Brando.AI.Agent.Guidance
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

    test "adds, replaces and removes the Figma token, showing only its last four characters",
         %{conn: conn, tenant: tenant} do
      {:ok, view, html} = live(conn, "/admin/config/mcp")
      assert html =~ ~s(data-testid="mcp-figma-form")
      refute html =~ ~s(data-testid="mcp-figma-status")

      view |> form("[data-testid=mcp-figma-form]", %{token: "figd_first-token-1111"}) |> render_submit()
      assert {:ok, "figd_first-token-1111"} = MCP.figma_token(tenant)

      html = render(view)
      assert html =~ "1111"
      refute html =~ "figd_first-token"
      refute html =~ ~s(data-testid="mcp-figma-form")
      # Adding a token does not turn the endpoint on
      refute MCP.enabled?(tenant)

      view |> element("[data-testid=mcp-figma-replace]") |> render_click()
      view |> form("[data-testid=mcp-figma-form]", %{token: "not a token"}) |> render_submit()
      assert {:ok, "figd_first-token-1111"} = MCP.figma_token(tenant)

      view |> form("[data-testid=mcp-figma-form]", %{token: "figd_second-token-2222"}) |> render_submit()
      assert {:ok, "figd_second-token-2222"} = MCP.figma_token(tenant)

      view |> element("[data-testid=mcp-figma-remove]") |> render_click()
      assert MCP.figma_token(tenant) == :error
      assert render(view) =~ ~s(data-testid="mcp-figma-form")

      details =
        Repo.all(
          from e in Brando.Activity.Event,
            where: e.schema == "Elixir.Brando.MCP.Setting",
            order_by: e.id,
            select: e.details
        )

      assert [%{"figma_token" => "added"}, %{"figma_token" => "added"}, %{"figma_token" => "removed"}] = details
      refute inspect(details) =~ "figd_"

      {:ok, _view, html} = live(conn, "/admin/config/activity")
      assert html =~ "Added the Figma access token"
      assert html =~ "Removed the Figma access token"
    end

    test "edits the guidance for building from Figma, as versions apart from the assistant's",
         %{conn: conn, current_user: user} do
      put_test_env(Brando.Figma, guidance: "Developers: header and footer are page chrome.")
      {:ok, _} = Guidance.save("The assistant's own guidance.", user)

      {:ok, view, html} = live(conn, "/admin/config/mcp")
      assert html =~ ~s(data-testid="mcp-figma-guidance-form")
      assert has_element?(view, "[data-testid=mcp-figma-guidance-code] pre", "page chrome")
      refute html =~ "The assistant&#39;s own guidance."
      refute has_element?(view, "[data-testid=mcp-figma-guidance-history]")

      form = "[data-testid=mcp-figma-guidance-form]"
      view |> form(form, %{text: "The top text is heading and intro."}) |> render_change()
      view |> form(form, %{text: "The top text is heading and intro."}) |> render_submit()
      assert Guidance.current(:figma).text == "The top text is heading and intro."
      assert Guidance.current().text == "The assistant's own guidance."
      assert has_element?(view, "[data-testid=mcp-figma-guidance-saved]")

      view |> form(form, %{text: "Credits go last."}) |> render_submit()
      assert {:ok, [%{text: "Credits go last."}, first]} = Guidance.history(user, kind: :figma)

      # An earlier version loads into the editor, unsaved until saved
      view |> element("[data-testid=mcp-figma-guidance-history] button[phx-value-id='#{first.id}']") |> render_click()
      assert has_element?(view, "#mcp-figma-guidance-text", "The top text is heading and intro.")
      assert Guidance.current(:figma).text == "Credits go last."

      view |> form(form, %{text: "The top text is heading and intro."}) |> render_submit()
      assert Guidance.current(:figma).text == "The top text is heading and intro."
      assert Guidance.current(:figma).note =~ "Restored"
    end

    test "shows the guidance for building from Figma read-only to a manager who may not configure the assistant",
         %{current_user: superuser} do
      {:ok, _} = Guidance.save("Credits go last.", superuser, kind: :figma)
      admin = Brando.Factory.insert(:random_user, role: :admin, config: %Brando.Users.UserConfig{})
      conn = log_in_user(build_conn(), admin)

      {:ok, view, html} = live(conn, "/admin/config/mcp")
      refute html =~ ~s(data-testid="mcp-figma-guidance-form")
      assert has_element?(view, "[data-testid=mcp-figma-guidance-readonly] pre", "Credits go last.")

      # The event alone changes nothing
      render_hook(view, "save_figma_guidance", %{"text" => "Changed"})
      assert Guidance.current(:figma).text == "Credits go last."
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

    test "an expired connection is marked in both lists", %{conn: conn, tenant: tenant} do
      switch!(tenant)
      connect!(conn, tenant)
      Repo.update_all(Grant, set: [inserted_at: DateTime.add(DateTime.utc_now(), -91 * 86_400, :second)])

      {:ok, _view, html} = live(conn, "/admin/users/security")
      assert html =~ ~s(data-testid="connected-app-expired")
      {:ok, _view, html} = live(conn, "/admin/config/mcp")
      assert html =~ ~s(data-testid="mcp-grant-expired")
    end

    test "turning the endpoint off says how many apps it disconnects", %{conn: conn, tenant: tenant} do
      switch!(tenant)
      connect!(conn, tenant)
      {:ok, view, _html} = live(conn, "/admin/config/mcp")
      assert has_element?(view, ~s([data-testid=mcp-disable][data-confirm*="1 connected app"]))
      view |> element("[data-testid=mcp-disable]") |> render_click()
      assert %Grant{revoked_reason: "endpoint_off"} = Repo.one!(Grant)
      refute render(view) =~ ~s(data-testid="mcp-grant")
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

      {:ok, view, html} = live(conn, "/admin/config/activity")
      assert has_element?(view, ".activity-person-line", "Test Client")
      assert has_element?(view, ".activity-person-line .activity-kind[data-kind=mcp]")
      assert html =~ "list_content_types"
      assert html =~ "Connected over MCP"
    end
  end
end
