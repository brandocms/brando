defmodule BrandoAdmin.AdminHostTest do
  # With several sites the admin answers on the endpoint's host only. Not
  # async: a site's 404 page reads a tenant schema this module creates, and
  # it renders through an endpoint put in the application environment.
  use Brando.ConnCase, async: false

  import Phoenix.LiveViewTest, only: [live: 2]

  alias Brando.SiteAssetsFixtures
  alias Brando.Tenant
  alias Brando.Tenant.Cache
  alias Brando.Test.AdminHostRouter, as: Router
  alias BrandoAdmin.AdminHost

  # `BrandoIntegrationWeb.Endpoint` has no `url`, so its host is Phoenix's default
  @admin_host "localhost"

  setup do
    Tenant.put_prefix(nil)
    Cache.clear()

    on_exit(fn ->
      Tenant.put_prefix(nil)
      Cache.clear()
    end)
  end

  describe "the admin socket's check_origin/1" do
    test "takes the endpoint's host only" do
      assert AdminHost.check_origin(URI.parse("https://localhost"))
      assert AdminHost.check_origin(URI.parse("http://LOCALHOST.:4000"))
      refute AdminHost.check_origin(URI.parse("https://beta.test"))
      refute AdminHost.check_origin(URI.parse("https://acme.localhost"))
      refute AdminHost.check_origin(URI.parse("https://unknown.example.com"))
    end

    test "refuses an origin with no host" do
      refute AdminHost.check_origin(URI.parse("null"))
      refute AdminHost.check_origin(%URI{})
    end

    test "is as strict with any tenancy mode" do
      for mode <- [:none, :single] do
        put_test_env(:tenancy_mode, mode)
        assert AdminHost.check_origin(URI.parse("https://localhost"))
        refute AdminHost.check_origin(URI.parse("https://beta.test"))
      end
    end
  end

  describe "with several sites, on another host than the endpoint's" do
    setup do
      put_test_env(:tenancy_mode, :multi)
      {:ok, beta} = SiteAssetsFixtures.create_site("Beta", "beta", "beta.test")
      site_404_page()
      %{beta: beta}
    end

    test "the admin's and MCP's paths answer as a missing path does: the site's own 404 page", %{beta: beta} do
      missing = request(:get, "/no-such-page", "beta.test")
      assert missing.status == 404
      assert missing.resp_body == "Not found on this site"
      assert request(:get, "/admin/no-such-route", "beta.test").resp_body == missing.resp_body

      for path <- [
            # the login page, an admin page, an admin LiveView, a controller page
            "/admin/login",
            "/admin/pages",
            "/admin/projects",
            "/admin/access-denied",
            "/admin/sites?x=1",
            # as the router decodes it
            "/%61dmin/login",
            # MCP, mounted by mcp_routes/0
            "/admin/mcp/authorize",
            "/mcp",
            "/mcp/beta/production",
            "/.well-known/oauth-protected-resource/mcp/beta/production",
            "/.well-known/oauth-authorization-server/mcp"
          ] do
        conn = request(:get, path, "beta.test")
        assert {conn.status, conn.resp_body} == {missing.status, missing.resp_body}, path
        assert conn.assigns.current_site.id == beta.id, path
        refute Map.has_key?(conn.assigns, :current_user), path
      end
    end

    test "a POST under the admin's path answers as a POST to a path with no route" do
      assert {:no_route, _conn} = request(:post, "/no-such-page", "beta.test")
      assert {:no_route, _conn} = request(:post, "/admin/login", "beta.test")
      assert {:no_route, _conn} = request(:post, "/admin/api/content/image/replace_crop", "beta.test")
    end

    test "the site may have a page of its own at /admin" do
      conn = request(:get, "/admin", "beta.test")
      assert {conn.status, conn.resp_body} == {200, "The site's own page at /admin"}
    end

    test "a host bound to nothing answers the plain 404, without a database query" do
      queries = count_queries()
      missing = request(:get, "/no-such-page", "unbound.test")
      assert {missing.status, missing.resp_body} == {404, "Not found"}

      for path <- ["/admin/login", "/admin/pages", "/admin/projects", "/mcp"] do
        conn = request(:get, path, "unbound.test")
        assert {conn.status, conn.resp_body} == {missing.status, missing.resp_body}, path
      end

      assert queries.() == 0
    end
  end

  describe "on the endpoint's host" do
    setup do
      put_test_env(:tenancy_mode, :multi)
      :ok
    end

    test "the admin answers with several sites as before" do
      assert admin_conn() |> get("/admin/login") |> html_response(200) =~ ~s(name="user[email]")

      assert admin_conn()
             |> post("/admin/login", %{"user" => %{"email" => "nobody@example.com", "password" => "wrong"}})
             |> redirected_to() == "/admin/login"

      assert admin_conn() |> get("/admin/pages") |> redirected_to() == "/admin/login"

      user = Brando.Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
      conn = Brando.Test.log_in_user(build_conn(), user)
      assert conn.host == @admin_host
      assert {:ok, _view, _html} = live(conn, "/admin/sites")
    end

    test "the admin answers on every host with one site or none" do
      put_test_env(:site_key, "beta")

      for mode <- [:none, :single], host <- ["beta.test", "unbound.test", @admin_host] do
        put_test_env(:tenancy_mode, mode)
        conn = %{build_conn() | host: host} |> get("/admin/login")
        assert html_response(conn, 200) =~ ~s(name="user[email]"), "#{mode} on #{host}"
      end
    end
  end

  defmodule ErrorHTML do
    @moduledoc false
    def render("404.html", _assigns), do: "Not found on this site"
  end

  defmodule ErrorEndpoint do
    @moduledoc false
    def config(:render_errors), do: [formats: [html: ErrorHTML]]
    def host, do: "localhost"
  end

  # The site's 404 page reads its content schema
  defp site_404_page do
    put_test_env(:use_default_errors, true)
    put_test_env(:endpoint_module, ErrorEndpoint)
    {:ok, tables} = Brando.Environments.StructureCloner.Postgres.tenant_tables("public")
    Brando.MigrationTemplates.create_environment("tenant_beta_production", tables)
  end

  defp request(method, path, host) do
    Tenant.put_prefix(nil)

    method
    |> Plug.Test.conn("https://#{host}#{path}")
    |> Router.call(Router.init([]))
  rescue
    error in Phoenix.Router.NoRouteError -> {:no_route, error.conn}
  after
    Tenant.put_prefix(nil)
  end

  # Queries this process runs from now on
  defp count_queries do
    test = self()
    id = "admin-host-queries-#{System.unique_integer([:positive])}"
    counter = :counters.new(1, [])

    :telemetry.attach(
      id,
      [:brando_integration, :repo, :query],
      fn _event, _measurements, _meta, _config -> if self() == test, do: :counters.add(counter, 1, 1) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)
    fn -> :counters.get(counter, 1) end
  end
end
