defmodule BrandoAdmin.NavBrandTest do
  # The navigation shows the selected site's frontend's admin_brand/0, else
  # client_brand. The login screen, where no site is selected, keeps
  # client_brand. Not async: it sets :client_brand and :site_frontends, and
  # registers sites in the tenant cache, which is the node's.
  use Brando.LiveCase, async: false

  alias Brando.Tenant
  alias Brando.Tenant.Registry

  @client_brand ~s(<span class="client-brand">Client</span>)

  defmodule Layouts do
    @moduledoc false
    use Phoenix.Component
    def root(assigns), do: ~H"{@inner_content}"
  end

  defmodule PageHTML do
    @moduledoc false
    use Phoenix.Component
  end

  defmodule Acme do
    @moduledoc false
    use Brando.Site.Frontend, root_layout: {Layouts, :root}, page_html: PageHTML

    def admin_brand, do: ~s(<span class="site-brand">Acme</span>)
  end

  defmodule AcmeStaging do
    @moduledoc false
    use Brando.Site.Frontend, root_layout: {Layouts, :root}, page_html: PageHTML

    def admin_brand, do: ~s(<span class="site-brand">Acme staging</span>)
  end

  defmodule Globex do
    @moduledoc false
    use Brando.Site.Frontend, root_layout: {Layouts, :root}, page_html: PageHTML
  end

  setup do
    put_test_env(:authorization_mode, :legacy)
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:client_brand, @client_brand)

    acme = site("brand-acme")
    globex = site("brand-globex")
    Tenant.Cache.warm()

    on_exit(fn ->
      Tenant.put_prefix(nil)
      Tenant.Cache.clear()
    end)

    %{acme: acme, globex: globex}
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

    for {environment, live} <- [{"production", true}, {"staging", false}] do
      {:ok, _} =
        Registry.create_environment(site, %{name: environment, key: environment, live: live}, actor: :system)
    end

    site
  end

  defp nav_brand(conn, site_key, environment_key \\ "production") do
    {:ok, nav, _html} =
      live_isolated(conn, BrandoAdmin.Nav,
        session: %{
          "user_token" => get_session(conn, :user_token),
          "brando_site_key" => site_key,
          "brando_environment_key" => environment_key,
          "current_url" => "/admin"
        }
      )

    nav |> element(".navigation-header .logo") |> render()
  end

  defp login_screen do
    build_conn() |> get("/admin/login") |> html_response(200)
  end

  test "a site whose frontend defines admin_brand/0 shows it", %{conn: conn} do
    put_test_env(:site_frontends, %{"brand-acme" => Acme, "brand-globex" => Globex})

    assert nav_brand(conn, "brand-acme") =~ ~s(<span class="site-brand">Acme</span>)
    refute nav_brand(conn, "brand-acme") =~ "client-brand"
    assert login_screen() =~ @client_brand
    refute login_screen() =~ "site-brand"
  end

  test "a site whose frontend defines none shows client_brand", %{conn: conn} do
    put_test_env(:site_frontends, %{"brand-acme" => Acme, "brand-globex" => Globex})

    assert nav_brand(conn, "brand-globex") =~ @client_brand
    refute nav_brand(conn, "brand-globex") =~ "site-brand"
    assert login_screen() =~ @client_brand
  end

  test "with no registry the navigation shows client_brand", %{conn: conn} do
    put_test_env(:site_frontends, nil)

    assert nav_brand(conn, "brand-acme") =~ @client_brand
    assert login_screen() =~ @client_brand
  end

  test "a {site, environment} entry applies to that environment", %{conn: conn} do
    put_test_env(:site_frontends, %{"brand-acme" => Acme, {"brand-acme", "staging"} => AcmeStaging})

    assert nav_brand(conn, "brand-acme", "staging") =~ "Acme staging"
    assert nav_brand(conn, "brand-acme", "production") =~ ~s(<span class="site-brand">Acme</span>)
    assert login_screen() =~ @client_brand
    refute login_screen() =~ "site-brand"
  end

  test "switching site shows the new site's brand", %{conn: conn} do
    put_test_env(:site_frontends, %{"brand-acme" => Acme, "brand-globex" => Globex})

    conn = post(conn, "/admin/environment", %{"site_key" => "brand-acme"})
    nav = page_nav(conn)
    assert :sys.get_state(nav.pid).socket.assigns.current_site.key == "brand-acme"
    assert nav |> element(".logo") |> render() =~ "site-brand"

    conn = conn |> recycle() |> post("/admin/environment", %{"site_key" => "brand-globex"})
    nav = page_nav(conn)
    assert :sys.get_state(nav.pid).socket.assigns.current_site.key == "brand-globex"
    assert nav |> element(".logo") |> render() =~ @client_brand
  end

  defp page_nav(conn) do
    {:ok, view, _} = live(recycle(conn), "/admin/sites")
    find_live_child(view, "brando-nav")
  end
end
