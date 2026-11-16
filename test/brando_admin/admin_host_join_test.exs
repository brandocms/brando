defmodule BrandoAdmin.AdminHostJoinTest do
  # An admin LiveView joined over the socket with several sites. Not async:
  # the join looks the route up before the LiveView knows the test is its
  # caller, so the tenancy mode is set for every process.
  use Brando.ConnCase, async: false

  import Phoenix.LiveViewTest

  # `BrandoIntegrationWeb.Endpoint` has no `url`, so its host is Phoenix's default
  @admin_host "localhost"

  setup do
    put_test_env(:tenancy_mode, :multi, global: true)
    user = Brando.Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    %{conn: Brando.Test.log_in_user(build_conn(), user)}
  end

  test "on the endpoint's host, an admin LiveView mounts and joins", %{conn: conn} do
    assert conn.host == @admin_host
    assert {:ok, view, _html} = live(conn, "/admin/sites")
    assert view.module == BrandoAdmin.Sites.SiteLive
  end

  test "a socket on a site's host cannot join an admin LiveView by naming the endpoint's host", %{conn: conn} do
    conn =
      Plug.Conn.put_private(conn, :live_view_connect_info, %{uri: URI.parse("https://acme.example.com/live/websocket")})

    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, "/admin/sites")
  end

  test "without the socket's URI, the join goes by the URL the client sends", %{conn: conn} do
    conn = Plug.Conn.put_private(conn, :live_view_connect_info, %{})
    assert {:ok, _view, _html} = live(conn, "/admin/sites")
  end
end
