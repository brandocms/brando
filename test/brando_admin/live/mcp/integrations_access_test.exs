defmodule BrandoAdmin.MCP.IntegrationsAccessTest do
  # Configuration → Integrations opens for those who manage webhooks or
  # connected AI tools, and shows each of those rows only to its managers.
  use Brando.LiveCase

  alias Brando.Authorization.{Boundary, Groups, Migration, Scope}
  alias Brando.Factory

  setup do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)
    Boundary.put_scope(nil)
    owner = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    {:ok, _} = Migration.run()
    %{scope: Scope.standalone(owner)}
  end

  defp member(c, keys) do
    user = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
    {:ok, group} = Groups.create(c.scope, %{name: "Group #{System.unique_integer([:positive])}"}, keys)
    {:ok, :ok} = Groups.add_member(c.scope, group.id, user.id)
    {user, log_in_user(build_conn(), user)}
  end

  defp menu_urls(user) do
    user
    |> BrandoAdmin.Menu.get_menu()
    |> List.wrap()
    |> Enum.flat_map(&urls/1)
  end

  defp urls(%{items: items} = item) when is_list(items), do: [item[:url] | Enum.flat_map(items, &urls/1)]
  defp urls(%{url: url}), do: [url]
  defp urls(items) when is_list(items), do: Enum.flat_map(items, &urls/1)
  defp urls(_), do: []

  test "with only brando.mcp.manage: the menu entry, the page and the MCP row, no webhooks", c do
    {user, conn} = member(c, ["brando.admin.access", "brando.mcp.manage"])

    assert "/admin/config/integrations" in menu_urls(user)

    {:ok, view, html} = live(conn, "/admin/config/integrations")
    assert has_element?(view, "#integration-mcp a[href='/admin/config/mcp']")
    refute has_element?(view, "#integration-webhooks")
    assert html =~ "Plausible"
    assert html =~ "Google Search Console"

    assert {:ok, _view, _html} = live(conn, "/admin/config/mcp")
    assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(conn, "/admin/config/webhooks")
  end

  test "with only brando.webhooks.manage: the webhooks row, no MCP", c do
    {user, conn} = member(c, ["brando.admin.access", "brando.webhooks.manage"])

    assert "/admin/config/integrations" in menu_urls(user)
    {:ok, view, _html} = live(conn, "/admin/config/integrations")
    assert has_element?(view, "#integration-webhooks")
    refute has_element?(view, "#integration-mcp")
    assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(conn, "/admin/config/mcp")
  end

  test "with neither: no menu entry and no page", c do
    {user, conn} = member(c, ["brando.admin.access", "brando.mcp.connect"])

    refute "/admin/config/integrations" in menu_urls(user)
    assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(conn, "/admin/config/integrations")
  end
end
