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

  # The test writes the site's cache keys, `{:tenant, prefix, key}`. They are
  # named here rather than through the process's prefix, which namespaces
  # nothing while tenancy is `:none`, as it is in setup and on_exit.
  defp preserve_tenant_cache(keys) do
    snapshot = Map.new(keys, &{{:tenant, @prefix, &1}, Cachex.get!(:cache, {:tenant, @prefix, &1})})
    on_exit(fn -> Enum.each(snapshot, &restore_tenant_cache/1) end)
  end

  defp restore_tenant_cache({key, nil}), do: Cachex.del!(:cache, key)
  defp restore_tenant_cache({key, cached}), do: Cachex.put!(:cache, key, cached)

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

  describe "renaming the identity" do
    setup do
      # Every other tenant table, empty: an identity save reaches services,
      # identifiers and the entries that render from the identity.
      "SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename <> 'pages'"
      |> Repo.query!()
      |> Map.fetch!(:rows)
      |> List.flatten()
      |> Enum.reject(&Tenant.SharedTables.member?/1)
      |> Enum.each(fn table ->
        escaped = String.replace(table, "\"", "\"\"")
        Repo.query!(~s|CREATE TABLE "#{@prefix}"."#{escaped}" (LIKE public."#{escaped}" INCLUDING ALL)|)
      end)

      :ok
    end

    # An identity, the cache holding it, and a page with a child under it,
    # their trails stored under the old name
    defp renamed_site(mode) do
      on_site(mode, %{})
      identity = Brando.Sites.create_default_identity("en")
      Brando.Cache.put(:identity, Brando.Cache.Identity.load()[:identity], :infinite)

      root = Brando.Repo.insert!(%Page{title: "About", uri: "about", language: :en, template: "default.html"})

      child =
        Brando.Repo.insert!(%Page{
          title: "Team",
          uri: "about/team",
          language: :en,
          template: "default.html",
          parent_id: root.id
        })

      {:ok, _} = Pages.update_breadcrumbs(root)

      %{identity: identity, root: root, child: child}
    end

    defp home_titles(pages), do: Enum.map(pages, &hd(Brando.Repo.get!(Page, &1.id).breadcrumbs)["title"])

    test "recomputes the language's stored trails in :multi" do
      c = renamed_site(:multi)
      assert home_titles([c.root, c.child]) == ["Organization name", "Organization name"]

      {:ok, _} = Brando.Sites.update_identity(c.identity, %{name: "Acme Identity"}, :system)

      assert home_titles([c.root, c.child]) == ["Acme Identity", "Acme Identity"]
    end

    test "leaves the trails alone when the name stays in :multi" do
      c = renamed_site(:multi)
      Brando.Repo.update_all(Page, set: [breadcrumbs: [%{"title" => "Stored", "uri" => "/"}]])

      {:ok, _} = Brando.Sites.update_identity(c.identity, %{email: "post@acme.test"}, :system)

      assert home_titles([c.root, c.child]) == ["Stored", "Stored"]
    end

    test "recomputes the trail of a live page under a trashed parent" do
      c = renamed_site(:multi)
      c.root |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Brando.Repo.update!()

      {:ok, _} = Brando.Sites.update_identity(c.identity, %{name: "Acme Identity"}, :system)

      assert home_titles([c.child]) == ["Acme Identity"]
    end

    test "leaves a trashed parent out of the trail" do
      c = renamed_site(:multi)
      {:ok, _} = Pages.delete_page(c.root.id, :system)

      {:ok, _} = Brando.Sites.update_identity(c.identity, %{name: "Acme Identity"}, :system)

      assert Brando.Repo.get!(Page, c.child.id).breadcrumbs == [
               %{"title" => "Acme Identity", "uri" => "/"},
               %{"title" => "Team", "uri" => "/about/team"}
             ]
    end

    test "recomputes after the identity cache rebuilds when saved in a transaction" do
      c = renamed_site(:multi)

      {:ok, {:ok, _}} =
        Brando.Repo.transaction(fn ->
          result = Brando.Sites.update_identity(c.identity, %{name: "Acme Identity"}, :system)
          # Read before the commit: the recompute waits for the cache's rebuild
          assert home_titles([c.root, c.child]) == ["Organization name", "Organization name"]
          result
        end)

      assert home_titles([c.root, c.child]) == ["Acme Identity", "Acme Identity"]
    end

    test "leaves the trails alone when the name stays and the identity cache is cold" do
      c = renamed_site(:multi)
      Brando.Repo.update_all(Page, set: [breadcrumbs: [%{"title" => "Stored", "uri" => "/"}]])
      Brando.Cache.put(:identity, nil, :infinite)

      {:ok, _} = Brando.Sites.update_identity(c.identity, %{email: "post@acme.test"}, :system)

      assert home_titles([c.root, c.child]) == ["Stored", "Stored"]
    end

    test "logs a recompute that raises and keeps the save" do
      c = renamed_site(:multi)
      # A trail entry is built from the page's uri
      Brando.Repo.insert!(%Page{title: "No uri", language: :en, template: "default.html"})
      later = Brando.Repo.insert!(%Page{title: "Contact", uri: "contact", language: :en, template: "default.html"})

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:ok, _} = Brando.Sites.update_identity(c.identity, %{name: "Acme Identity"}, :system)
        end)

      assert log =~ "breadcrumbs"
      # The page that failed does not stop the others
      assert home_titles([c.root, c.child, later]) == ["Acme Identity", "Acme Identity", "Acme Identity"]
    end

    test "evicts the cached page queries" do
      c = renamed_site(:multi)
      {:ok, _} = Pages.get_page(%{matches: %{id: c.child.id}, cache: true})
      {:ok, _} = Pages.list_pages(%{cache: true})

      {:ok, _} = Brando.Sites.update_identity(c.identity, %{name: "Acme Identity"}, :system)

      {:ok, child} = Pages.get_page(%{matches: %{id: c.child.id}, cache: true})
      {:ok, pages} = Pages.list_pages(%{cache: true})
      assert hd(child.breadcrumbs)["title"] == "Acme Identity"
      assert Enum.map(pages, &hd(&1.breadcrumbs)["title"]) == ["Acme Identity", "Acme Identity"]
    end

    test "leaves the trails alone in :single" do
      c = renamed_site(:single)
      Brando.Repo.update_all(Page, set: [breadcrumbs: [%{"title" => "Stored", "uri" => "/"}]])

      {:ok, _} = Brando.Sites.update_identity(c.identity, %{name: "Acme Identity"}, :system)

      assert home_titles([c.root, c.child]) == ["Stored", "Stored"]
    end
  end
end
