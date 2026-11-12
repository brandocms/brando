defmodule Brando.Sites.SiteNameTest do
  # Not async: it creates a tenant schema and registers a site in the tenant
  # cache, which is the node's.
  use Brando.ConnCase, async: false

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Brando.Pages
  alias Brando.Pages.Page
  alias Brando.Tenant
  alias Brando.Tenant.Registry

  @site_key "site-name-acme"
  @prefix "tenant_site-name-acme_production"

  setup do
    {:ok, site} =
      Registry.create_site(%{
        name: "Acme Site",
        key: @site_key,
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, _environment} =
      Registry.create_environment(site, %{name: "Production", key: "production", live: true}, actor: :system)

    Repo.query!(~s(CREATE SCHEMA "#{@prefix}"))
    Repo.query!(~s|CREATE TABLE "#{@prefix}".pages (LIKE public.pages INCLUDING ALL)|)

    preserve_tenant_cache([:identity, :seo])

    on_exit(fn ->
      Tenant.put_prefix(nil)
      Tenant.Cache.clear()
    end)

    %{site: site}
  end

  # `preserve_cache/1` restores in the on_exit process, which has no prefix.
  defp preserve_tenant_cache(keys) do
    snapshot = Tenant.with_prefix(@prefix, fn -> Map.new(keys, &{&1, Brando.Cache.get(&1)}) end)

    on_exit(fn ->
      Tenant.with_prefix(@prefix, fn ->
        for {key, cached} <- snapshot, do: restore_tenant_cache(key, cached)
      end)
    end)
  end

  defp restore_tenant_cache(key, nil), do: Brando.Cache.del(key)
  defp restore_tenant_cache(key, cached), do: Brando.Cache.put(key, cached, :infinite)

  defp on_site(mode, identities) do
    put_test_env(:tenancy_mode, mode)
    if mode == :single, do: put_test_env(:site_key, @site_key)
    # Registry writes warm the tenant cache after commit, which the sandbox never does
    Tenant.Cache.warm()
    Tenant.put_prefix(@prefix)

    Brando.Cache.put(:identity, identities, :infinite)

    Brando.Cache.put(
      :seo,
      %{
        "en" => %Brando.Sites.SEO{
          fallback_meta_title: "Fallback",
          fallback_meta_description: "Description",
          fallback_meta_image: nil
        }
      },
      :infinite
    )
  end

  defp og_site_name(conn) do
    assigns = %{conn: conn}
    html = rendered_to_string(~H|<Brando.HTML.render_meta conn={@conn} />|)

    case Regex.run(~r/<meta property="og:site_name" content="([^"]*)">/, html) do
      [_, name] -> name
      nil -> nil
    end
  end

  defp meta_conn, do: %Plug.Conn{assigns: %{language: "en"}}

  defp home_title do
    page = Brando.Repo.insert!(%Page{title: "About", uri: "about", language: :en, template: "default.html"})
    {:ok, page} = Pages.update_breadcrumbs(page)
    [%{"title" => title, "uri" => "/"}, %{"title" => "About"}] = page.breadcrumbs
    title
  end

  describe "og:site_name in :multi" do
    test "is the identity's name for the language" do
      on_site(:multi, %{"en" => %{name: "Acme Identity", links: [], metas: []}})
      assert og_site_name(meta_conn()) == "Acme Identity"
    end

    test "is the site's name when the identity has none" do
      on_site(:multi, %{"en" => %{name: " ", links: [], metas: []}})
      assert og_site_name(meta_conn()) == "Acme Site"

      on_site(:multi, %{})
      assert og_site_name(meta_conn()) == "Acme Site"
    end

    test "is app_name when neither has one", %{site: site} do
      on_site(:multi, %{})
      # A site's changeset requires a name: blank it in the tenant cache only
      :persistent_term.put({:brando, :site, @site_key}, %{site | name: ""})

      assert og_site_name(meta_conn()) == "MyApp"
    end

    test "a value the page set still wins" do
      on_site(:multi, %{"en" => %{name: "Acme Identity", links: [], metas: []}})
      conn = Brando.Plug.HTML.put_meta(meta_conn(), "og:site_name", "Set by the page")
      assert og_site_name(conn) == "Set by the page"
    end
  end

  describe "og:site_name in :none and :single" do
    test "is app_name in :none" do
      put_test_env(:tenancy_mode, :none)
      assert og_site_name(meta_conn()) == "MyApp"
    end

    test "is app_name in :single" do
      on_site(:single, %{"en" => %{name: "Acme Identity", links: [], metas: []}})
      assert og_site_name(meta_conn()) == "MyApp"
    end
  end

  describe "the breadcrumbs' home title in :multi" do
    test "is the identity's name for the page's language" do
      on_site(:multi, %{"en" => %{name: "Acme Identity"}})
      assert home_title() == "Acme Identity"
    end

    test "is the site's name when the identity has none" do
      on_site(:multi, %{})
      assert home_title() == "Acme Site"
    end

    test "is app_name when neither has one", %{site: site} do
      on_site(:multi, %{})
      :persistent_term.put({:brando, :site, @site_key}, %{site | name: nil})
      assert home_title() == "MyApp"
    end
  end

  describe "the breadcrumbs' home title in :none and :single" do
    test "is app_name in :none" do
      put_test_env(:tenancy_mode, :none)
      page = Brando.Factory.insert(:page, title: "About", uri: "about")
      {:ok, page} = Pages.update_breadcrumbs(page)
      assert [%{"title" => "MyApp", "uri" => "/"} | _] = page.breadcrumbs
    end

    test "is app_name in :single" do
      on_site(:single, %{"en" => %{name: "Acme Identity"}})
      assert home_title() == "MyApp"
    end
  end
end
