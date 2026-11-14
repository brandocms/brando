defmodule BrandoAdmin.SiteLanguagesLiveTest do
  # The admin's screens on a multi-site installation follow the site's own
  # languages (`Brando.Languages`). Acme uses English and Norwegian, Beta
  # English only. Not async: it registers sites in the tenant cache, which is
  # the node's.
  use Brando.LiveCase, async: false

  alias Brando.Tenant
  alias Brando.Tenant.Registry

  setup %{current_user: user} do
    put_test_env(:authorization_mode, :legacy)
    put_test_env(:tenancy_mode, :multi)
    Tenant.put_prefix(nil)
    Tenant.Cache.clear()

    site("Acme", "acme", ["en", "no"], "no")
    site("Beta", "beta", ["en"], "en")
    Tenant.Cache.warm()

    # The screens read the sites' content
    for prefix <- ["tenant_acme_production", "tenant_beta_production"], do: clone_public_tables(prefix)

    on_exit(fn ->
      Tenant.put_prefix(nil)
      Tenant.Cache.clear()
    end)

    {:ok, user} = Brando.Users.update_user(user, %{config: %{content_language: "no"}}, :system, show_notification: false)
    %{current_user: user}
  end

  defp site(name, key, languages, default_language) do
    {:ok, site} =
      Registry.create_site(%{
        name: name,
        key: key,
        languages: languages,
        default_language: default_language,
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, _} = Registry.create_environment(site, %{name: "Production", key: "production", live: true}, actor: :system)
  end

  # The tenant schema the prefix names, with the content tables; rolled back
  # with the test's transaction
  defp clone_public_tables(prefix) do
    Repo.query!(~s|CREATE SCHEMA "#{prefix}"|)
    %{rows: rows} = Repo.query!("SELECT tablename FROM pg_tables WHERE schemaname = 'public'")

    for [table] <- rows, not Tenant.SharedTables.member?(table) do
      Repo.query!(~s|CREATE TABLE "#{prefix}"."#{table}" (LIKE public."#{table}" INCLUDING ALL)|)
    end
  end

  defp stored_content_language(user), do: Brando.Repo.get!(Brando.Users.User, user.id).config.content_language

  describe "an editor whose content language the site lacks" do
    test "works in the site's default language after a live navigation into it", %{conn: conn, current_user: user} do
      {:ok, nav, _html} =
        live_isolated(conn, BrandoAdmin.Nav,
          session: %{
            "user_token" => get_session(conn, :user_token),
            "brando_site_key" => "beta",
            "brando_environment_key" => "production",
            "current_url" => "/admin"
          }
        )

      assert :sys.get_state(nav.pid).socket.assigns.current_user.config.content_language == "en"
      assert stored_content_language(user) == "en"
    end

    test "works in the site's default language when a link names the site", %{conn: conn, current_user: user} do
      # The session's site is Acme, which has Norwegian
      conn = post(conn, "/admin/environment", %{"site_key" => "acme"})
      assert stored_content_language(user) == "no"

      {:ok, view, _html} = live(recycle(conn), "/admin/pages?brando_site_key=beta")

      assert :sys.get_state(view.pid).socket.assigns.current_site.key == "beta"
      assert :sys.get_state(view.pid).socket.assigns.current_user.config.content_language == "en"
      assert stored_content_language(user) == "en"
    end
  end

  test "the content-language switch is rendered on a site with two languages and not on one with one", %{conn: conn} do
    conn = post(conn, "/admin/environment", %{"site_key" => "acme"})
    {:ok, view, _html} = live(recycle(conn), "/admin/pages")
    assert has_element?(view, ".content-language-selector")

    view |> element(".content-language-selector .current-language") |> render_click()

    assert view
           |> element(".content-language-selector .languages")
           |> render()
           |> Floki.parse_fragment!()
           |> Floki.find("button")
           |> Enum.map(&Floki.text/1)
           |> Enum.map(&String.trim/1) ==
             ["English", "Norsk"]

    conn = conn |> recycle() |> post("/admin/environment", %{"site_key" => "beta"})
    {:ok, view, _html} = live(recycle(conn), "/admin/pages")
    refute has_element?(view, ".content-language-selector")
  end

  test "the search screen's language filter offers the site's languages", %{conn: conn} do
    conn = post(conn, "/admin/environment", %{"site_key" => "acme"})
    {:ok, view, _html} = live(recycle(conn), "/admin/search")

    options =
      view
      |> element("#search-language")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("option")
      |> Enum.map(&Floki.attribute(&1, "value"))
      |> List.flatten()

    assert options == ["", "en", "no"]

    conn = conn |> recycle() |> post("/admin/environment", %{"site_key" => "beta"})
    {:ok, view, _html} = live(recycle(conn), "/admin/search")
    refute has_element?(view, "#search-language")
  end
end
