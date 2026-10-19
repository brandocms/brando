defmodule BrandoAdmin.MenuConfigItemsAccessTest do
  # With group authorization, an application's Configuration item
  # (`BrandoAdmin.Menu.config_item/3`) shows to those who may open its route:
  # the requirement its LiveView declares decides, and a LiveView that
  # declares none opens for no one.
  use Brando.LiveCase

  alias Brando.Authorization.{Boundary, Groups, Migration, Scope}
  alias Brando.Factory
  alias BrandoAdmin.CommandPalette

  setup do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)
    put_test_env(:admin_module, BrandoIntegrationConfigAdmin)
    Boundary.put_scope(nil)
    owner = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    {:ok, _} = Migration.run()
    %{owner: owner, scope: Scope.standalone(owner)}
  end

  defp member(c, keys) do
    user = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
    {:ok, group} = Groups.create(c.scope, %{name: "Group #{System.unique_integer([:positive])}"}, keys)
    {:ok, :ok} = Groups.add_member(c.scope, group.id, user.id)
    {user, log_in_user(build_conn(), user)}
  end

  defp configuration_urls(user) do
    user
    |> BrandoAdmin.Menu.get_menu()
    |> Enum.flat_map(& &1.items)
    |> Enum.find(%{items: []}, &(&1[:key] == :configuration))
    |> Map.fetch!(:items)
    |> Enum.map(& &1.url)
  end

  test "the item shows to those granted what its LiveView requires, and the page opens", c do
    {user, conn} = member(c, ["brando.admin.access", "brando.utilities.read"])

    assert "/admin/config/shop" in configuration_urls(user)
    assert Enum.any?(CommandPalette.context(user).settings, &(&1.url == "/admin/config/shop"))
    assert {:ok, _view, html} = live(conn, "/admin/config/shop")
    assert html =~ "Shop settings"
  end

  test "the item is hidden from those without it, and the page is denied", c do
    {user, conn} = member(c, ["brando.admin.access"])

    refute "/admin/config/shop" in configuration_urls(user)
    assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(conn, "/admin/config/shop")
  end

  test "roles: do not apply; an editor-role member without the grant does not see an editor item", c do
    {user, _conn} = member(c, ["brando.admin.access"])

    refute "/admin/config/product-blocks" in configuration_urls(%{user | role: :editor})
  end

  test "an item whose LiveView declares no requirement is hidden from everyone, as the page is", c do
    refute "/admin/config/undeclared" in configuration_urls(c.owner)

    conn = log_in_user(build_conn(), c.owner)
    assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(conn, "/admin/config/undeclared")
  end
end
