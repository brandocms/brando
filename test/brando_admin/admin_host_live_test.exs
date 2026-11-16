defmodule BrandoAdmin.AdminHostLiveTest do
  # A site's LiveView at a path an admin route also matches, mounted over HTTP
  # and joined over the socket on the site's host. Not async: it starts an
  # endpoint of its own from the application environment.
  use Brando.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Brando.Test.AdminHostLiveEndpoint

  @endpoint AdminHostLiveEndpoint

  setup do
    put_test_env(AdminHostLiveEndpoint,
      secret_key_base: String.duplicate("adminhostlive", 6),
      live_view: [signing_salt: "adminhostlivesalt"],
      server: false
    )

    start_supervised!(AdminHostLiveEndpoint)
    # The join looks the route up before the LiveView knows the test is its caller
    put_test_env(:tenancy_mode, :multi, global: true)
    :ok
  end

  test "on a site's host, the site's LiveView mounts and joins at an admin path" do
    for path <- ["/admin/projects", "/admin/login", "/mcp", "/about"] do
      conn = %{build_conn() | host: "beta.test"} |> init_test_session(%{})

      assert {:ok, view, html} = live(conn, path), path
      assert html =~ "A live page of the site"
      assert view.module == Brando.Test.AdminHostSiteLive
      assert render(view) =~ "A live page of the site"
    end
  end
end
