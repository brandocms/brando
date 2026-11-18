defmodule Brando.Cache.ClearContentTest do
  # Content written outside `Brando.Query` (a seed, a data migration,
  # `Repo.update_all`) reaches no eviction: `Brando.Cache.clear_content/1`
  # empties what rendered content reads, here and on the other nodes. One
  # node in a test run: a refresh "from another node" is a message that
  # carries another node's origin, and a row "a script wrote" is written with
  # the repo.
  #
  # Synchronous: it rebuilds the site caches and empties the query cache.
  use Brando.ConnCase, async: false

  alias Brando.Cache
  alias Brando.Cache.Freshness
  alias Brando.Cache.Query, as: QueryCache
  alias Brando.CacheSync
  alias Brando.Content.Module
  alias Brando.{Factory, Repo}
  alias Brando.Pages.{Fragment, Page}

  @other_node "another-node"
  @tokens {Brando.Cache.Freshness, :tokens}
  @site_caches [:identity, :seo, :globals, :palettes, :navigation]

  setup do
    preserve_cache([:globals, :navigation, :palettes, :palettes_css, :identity, :seo, @tokens])
    preserve_query_cache([Page, Fragment, Module])
    CacheSync.sync()
    Phoenix.PubSub.subscribe(Brando.pubsub(), CacheSync.topic())
    on_exit(fn -> CacheSync.sync() end)
    %{user: Factory.insert(:random_user, role: :superuser)}
  end

  describe "clear_content/1" do
    test "a cached page shows what a script wrote with Repo.update_all once it is called" do
      page = Factory.insert(:page, title: "Before", uri: "clear-content")
      opts = %{matches: %{id: page.id}, cache: {:ttl, :infinite}}

      assert {:ok, %{title: "Before"}} = Brando.Pages.get_page(opts)
      {1, _} = Repo.update_all(from(p in Page, where: p.id == ^page.id), set: [title: "After"])
      assert {:ok, %{title: "Before"}} = Brando.Pages.get_page(opts)

      assert {:ok, _summary} = Cache.clear_content()

      assert {:ok, %{title: "After"}} = Brando.Pages.get_page(opts)
    end

    test "empties the query cache's lists and entries and says how many" do
      pages = Page.__schema__(:source)
      fragments = Fragment.__schema__(:source)
      modules = Module.__schema__(:source)
      keys = [{:list, pages, "a"}, {:single, pages, "b", 1}, {:list, fragments, "c"}, {:single, modules, "d", 2}]
      for key <- keys, do: Cachex.put(:query, key, :cached)

      assert {:ok, %{query_entries: count, scope: :site}} = Cache.clear_content()

      assert count >= length(keys)
      assert cached(keys) == [false, false, false, false]
    end

    test "rebuilds identity, SEO, globals, palettes and menus from the database", c do
      {:ok, set} = Brando.Sites.create_global_set(global_set("system", "Old", c.user), c.user)

      {:ok, menu} =
        Brando.Navigation.create_menu(%{status: :published, title: "Old", key: "main", language: "en", items: []}, c.user)

      {:ok, palette} = Brando.Content.create_palette(palette("old"), c.user)
      {:ok, identity} = Brando.Sites.get_identity(%{matches: %{language: "en"}})
      {:ok, seo} = Brando.Sites.get_seo(%{matches: %{language: "en"}})

      # A script writes them with the repo
      set.vars |> hd() |> Ecto.Changeset.change(value: "New") |> Repo.update!()
      menu |> Ecto.Changeset.change(title: "New") |> Repo.update!()
      palette |> Ecto.Changeset.change(key: "new") |> Repo.update!()
      identity |> Ecto.Changeset.change(name: "New name") |> Repo.update!()
      seo |> Ecto.Changeset.change(fallback_meta_title: "New title") |> Repo.update!()

      assert Brando.Sites.global("en", "system", "text").value == "Old"
      assert Cache.Identity.get("en").name != "New name"

      assert {:ok, %{site_caches: caches}} = Cache.clear_content()
      assert Enum.sort(caches) == Enum.sort(@site_caches)

      assert Brando.Sites.global("en", "system", "text").value == "New"
      assert Cache.Navigation.get("main", "en").title == "New"
      assert "new" in Enum.map(Cache.Palettes.get(), & &1.key)
      assert Phoenix.HTML.safe_to_string(Cache.Palettes.get_css()) =~ "site-new"
      assert Cache.Identity.get("en").name == "New name"
      assert Cache.SEO.get("en").fallback_meta_title == "New title"
    end

    test "leaves the other sites' query cache entries, and all_sites: true empties them too" do
      put_test_env(:tenancy_mode, :multi, global: true)
      pages = Page.__schema__(:source)
      here = "tenant_acme_production"

      keys = [
        {:tenant, here, {:list, pages, "a"}},
        {:tenant, here, {:single, pages, "b", 1}},
        {:tenant, "tenant_other_production", {:list, pages, "c"}},
        {:list, pages, "d"}
      ]

      for key <- keys, do: Cachex.put(:query, key, :cached)

      # The query cache alone: the site caches would read tables this test
      # database has no schema for
      assert 2 = Brando.Tenant.with_prefix(here, &QueryCache.clear/0)
      assert cached(keys) == [false, false, true, true]

      assert QueryCache.clear_all() >= 2
      assert cached(keys) == [false, false, false, false]
    end

    test "with all_sites: true, rebuilds the site caches and empties the whole query cache", c do
      {:ok, set} = Brando.Sites.create_global_set(global_set("system", "Old", c.user), c.user)
      set.vars |> hd() |> Ecto.Changeset.change(value: "New") |> Repo.update!()
      key = {:tenant, "tenant_gone_production", {:list, Page.__schema__(:source), "a"}}
      Cachex.put(:query, key, :cached)

      assert {:ok, %{scope: :all, site_caches: caches}} = Cache.clear_content(all_sites: true)

      assert Enum.sort(caches) == Enum.sort(@site_caches)
      assert cached([key]) == [false]
      assert Brando.Sites.global("en", "system", "text").value == "New"
    end

    test "refuses an option it does not know" do
      assert_raise ArgumentError, fn -> Cache.clear_content(all: true) end
    end
  end

  describe "the other nodes" do
    test "hear the clear once it has committed, and nothing of one rolled back" do
      assert {:ok, _} =
               Repo.transaction(fn ->
                 {:ok, _} = Cache.clear_content()
                 refute_received {:brando_cache_sync, _, _}
               end)

      assert_received {:brando_cache_sync, origin, {QueryCache, {:clear, nil}}}
      assert origin == CacheSync.origin()
      for cache <- @site_caches, do: assert_received({:brando_cache_sync, _, {Cache, {^cache, nil}}})

      assert {:error, :undone} =
               Repo.transaction(fn ->
                 {:ok, _} = Cache.clear_content()
                 Repo.rollback(:undone)
               end)

      CacheSync.sync()
      refute_received {:brando_cache_sync, _, {QueryCache, _}}
    end

    test "with all_sites: true, hear that every site's query cache goes" do
      {:ok, _} = Cache.clear_content(all_sites: true)
      assert_received {:brando_cache_sync, _, {QueryCache, {:clear, :all}}}
    end

    test "a clear from another node empties this node's query cache under its site only" do
      put_test_env(:tenancy_mode, :multi, global: true)
      pages = Page.__schema__(:source)
      here = "tenant_acme_production"

      keys = [
        {:tenant, here, {:list, pages, "a"}},
        {:tenant, "tenant_other_production", {:list, pages, "b"}},
        {:list, pages, "c"}
      ]

      for key <- keys, do: Cachex.put(:query, key, :cached)

      remote_refresh({QueryCache, {:clear, here}})
      assert cached(keys) == [false, true, true]

      remote_refresh({QueryCache, {:clear, nil}})
      assert cached(keys) == [false, true, false]

      Cachex.put(:query, hd(keys), :cached)
      remote_refresh({QueryCache, {:clear, :all}})
      assert cached(keys) == [false, false, false]
    end

    test "this node's own clear is skipped: its cache is already empty" do
      key = {:list, Page.__schema__(:source), "a"}
      Cachex.put(:query, key, :cached)

      remote_refresh(CacheSync.origin(), {QueryCache, {:clear, nil}})

      assert cached([key]) == [true]
    end

    test "a render job queued after the clear evicts the lists renders read on a node that has not heard of it" do
      source = Fragment.__schema__(:source)
      before = Freshness.attach(%{})["query_sources"][source]

      {:ok, _} = Cache.clear_content()

      token = Freshness.attach(%{})["query_sources"][source]
      assert token && token != before

      # As on a node that has not heard: a list cached before, and the token unknown
      stale = {:list, source, "stale"}
      Cachex.put(:query, stale, :cached)
      Cache.del(@tokens)

      :ok = Cache.ensure_fresh(%{"query_sources" => %{source => token}})
      assert cached([stale]) == [false]
    end
  end

  describe "on a multi-site install" do
    defmodule Migrator do
      @behaviour Brando.Environments.Migrator

      @impl true
      def migrate(_site, _environment), do: {:ok, []}
    end

    @prefixes ~w(tenant_acme_production tenant_acme_staging)

    setup %{user: user} do
      root = Path.join(System.tmp_dir!(), "brando-clear-content-#{System.unique_integer([:positive])}")
      put_test_env(:media_path, Path.join(root, "media"))
      put_test_env(:sites_path, Path.join(root, "sites"))
      put_test_env(:tenant_migrator, Migrator)
      put_test_env(:tenant_structure_cloner, Brando.TenantCloners)
      put_test_env(:environment_schema_cloner, Brando.TenantCloners)
      put_test_env(:tenancy_mode, :multi, global: true)
      Brando.Tenant.put_prefix(nil)
      Brando.Tenant.Cache.clear()

      on_exit(fn ->
        File.rm_rf(root)
        Brando.Tenant.put_prefix(nil)
        Brando.Tenant.Cache.clear()
        Brando.TenantCaches.clear(@prefixes)
      end)

      {:ok, _site} =
        Brando.Tenant.Setup.create_site(
          %{name: "Acme", key: "acme", languages: ["en"], default_language: "en", status: :active},
          user,
          environments: [
            %{name: "Production", key: "production", live: true, domain: "acme.test"},
            %{name: "Staging", key: "staging", live: false, domain: "staging.acme.test"}
          ]
        )

      :ok
    end

    test "clears the current environment's caches only, and all_sites: true every environment's" do
      [production, staging] = @prefixes
      pages = Page.__schema__(:source)

      for prefix <- @prefixes do
        Brando.Tenant.with_prefix(prefix, fn ->
          Cache.put(:globals, :stale, :infinite)
          Cachex.put(:query, {:tenant, prefix, {:list, pages, "a"}}, :cached)
        end)
      end

      assert {:ok, %{scope: :site}} = Brando.Tenant.with_prefix(production, fn -> Cache.clear_content() end)

      assert stale_globals?() == [false, true]
      assert cached(for p <- @prefixes, do: {:tenant, p, {:list, pages, "a"}}) == [false, true]

      assert {:ok, %{scope: :all}} = Brando.Tenant.with_prefix(production, &clear_all_sites/0)

      assert stale_globals?() == [false, false]
      assert cached([{:tenant, staging, {:list, pages, "a"}}]) == [false]
    end

    test "outside every site, clears the unprefixed query cache and rebuilds no site cache" do
      key = {:list, Page.__schema__(:source), "a"}
      Cachex.put(:query, key, :cached)

      assert {:ok, %{scope: :site, site_caches: []}} = Cache.clear_content()
      assert cached([key]) == [false]
    end
  end

  defp clear_all_sites, do: Cache.clear_content(all_sites: true)

  defp stale_globals?,
    do: Enum.map(@prefixes, fn prefix -> Brando.Tenant.with_prefix(prefix, fn -> Cache.get(:globals) == :stale end) end)

  defp cached(keys), do: Enum.map(keys, &match?({:ok, :cached}, Cachex.get(:query, &1)))

  defp send_remote(origin, refresh) do
    Phoenix.PubSub.broadcast(Brando.pubsub(), CacheSync.topic(), {:brando_cache_sync, origin, refresh})
  end

  defp remote_refresh(origin \\ @other_node, refresh) do
    send_remote(origin, refresh)
    CacheSync.sync()
  end

  defp global_set(key, value, user) do
    %{
      label: key,
      key: key,
      language: "en",
      creator_id: user.id,
      vars: [%{type: "text", label: "Text", key: "text", value: value}]
    }
  end

  defp palette(key),
    do: %{
      name: key,
      key: key,
      namespace: "site",
      status: :published,
      colors: [%{name: "Red", key: "red", hex_value: "#ff0000"}]
    }
end
