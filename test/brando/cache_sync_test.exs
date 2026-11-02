defmodule Brando.CacheSyncTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Assets.SiteAssets
  alias Brando.CacheSync
  alias Brando.Content.SharedLibrary
  alias Brando.Environments.Environment
  alias Brando.SiteAssetsFixtures
  alias Brando.Sites.Site
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry

  # One node in a test run: a refresh "from another node" is a message that
  # names a node other than this one.
  @other_node :"brando@other-node"

  setup do
    put_test_env(:tenancy_mode, :multi)
    Cache.clear()
    SharedLibrary.Cache.clear()
    Phoenix.PubSub.subscribe(Brando.pubsub(), CacheSync.topic())

    on_exit(fn ->
      CacheSync.sync()
      Cache.clear()
      SharedLibrary.Cache.clear()
    end)

    :ok
  end

  describe "the tenant registry" do
    test "a write tells the other nodes" do
      {:ok, site} = Registry.create_site(site_attrs("acme"))
      assert_received {:brando_cache_sync, origin, {Cache, :registry}}
      assert origin == node()

      {:ok, _site} = Registry.update_site(site, %{status: :suspended})
      assert_received {:brando_cache_sync, _origin, {Cache, :registry}}
    end

    test "a refresh from another node warms this node's cache" do
      site = insert_site!("acme")
      environment = insert_environment!(site, "production", "old.acme.test")
      Cache.warm()

      # Another node moves the host
      environment |> Environment.changeset(%{domain: "new.acme.test"}) |> Repo.update!()

      assert Cache.get_env_by_domain("old.acme.test")
      remote_refresh({Cache, :registry})

      refute Cache.get_env_by_domain("old.acme.test")
      assert {%Site{key: "acme"}, %Environment{key: "production"}} = Cache.get_env_by_domain("new.acme.test")
    end

    test "a site another node suspends stops answering here" do
      site = insert_site!("acme")
      insert_environment!(site, "production", "www.acme.test")
      Cache.warm()

      site |> Site.changeset(%{status: :suspended}) |> Repo.update!()
      remote_refresh({Cache, :registry})

      refute Cache.get_env_by_domain("www.acme.test")
      refute Cache.get_live_env("acme")
    end

    test "this node's own messages are skipped: its cache is already fresh" do
      site = insert_site!("acme")
      environment = insert_environment!(site, "production", "old.acme.test")
      Cache.warm()

      environment |> Environment.changeset(%{domain: "new.acme.test"}) |> Repo.update!()
      Phoenix.PubSub.broadcast(Brando.pubsub(), CacheSync.topic(), {:brando_cache_sync, node(), {Cache, :registry}})
      CacheSync.sync()

      assert Cache.get_env_by_domain("old.acme.test")
    end

    test "the other nodes hear of a write only once its transaction commits" do
      Brando.Repo.transaction(fn ->
        {:ok, _site} = Registry.create_site(site_attrs("acme"))
        Cache.invalidate()
        refute_received {:brando_cache_sync, _origin, _refresh}
      end)

      assert_received {:brando_cache_sync, _origin, {Cache, :registry}}
      refute_received {:brando_cache_sync, _origin, _refresh}

      Brando.Repo.transaction(fn ->
        {:ok, _site} = Registry.create_site(site_attrs("rolled-back"))
        Brando.Repo.rollback(:undone)
      end)

      refute_received {:brando_cache_sync, _origin, _refresh}
      refute Cache.get_site("rolled-back")
    end

    test "a burst of refreshes from other nodes warms once" do
      for _ <- 1..25, do: send_remote({Cache, :registry})

      state = :sys.get_state(CacheSync)
      assert state.pending == %{{Cache, :registry} => 1}
      assert is_reference(state.timer)

      CacheSync.sync()
      assert :sys.get_state(CacheSync).pending == %{}
    end

    test "a pending refresh runs on its own after the debounce" do
      site = insert_site!("acme")
      insert_environment!(site, "production", "www.acme.test")
      refute Cache.get_site("acme")

      send_remote({Cache, :registry})

      assert eventually(fn -> Cache.get_site("acme") end)
    end

    test "an unknown cache is ignored" do
      send_remote({Brando.Users, :registry})
      assert :sys.get_state(CacheSync).pending == %{}
    end
  end

  describe "site assets" do
    setup do
      root = Path.join(System.tmp_dir!(), "brando-cache-sync-#{System.unique_integer([:positive])}")
      put_test_env(:tenancy_mode, :none)
      put_test_env(:site_assets_path, Path.join(root, "site_assets"))
      SiteAssets.invalidate_cache()

      on_exit(fn ->
        File.rm_rf(root)
        SiteAssets.invalidate_cache()
      end)

      :ok
    end

    test "activating and deactivating a set tells the other nodes" do
      {:ok, registered} = register_set("20260816_one")

      assert {:ok, _active} = SiteAssets.activate_set(registered.id)
      assert_received {:brando_cache_sync, _origin, {SiteAssets, {:active, :standalone}}}

      assert :ok = SiteAssets.deactivate()
      assert_received {:brando_cache_sync, _origin, {SiteAssets, {:active, :standalone}}}
    end

    test "a set another node activates is served here" do
      {:ok, first} = register_set("20260816_one")
      {:ok, second} = register_set("20260816_two")
      {:ok, _active} = SiteAssets.activate_set(first.id)
      first_id = first.id
      assert %{set: %{id: ^first_id}} = SiteAssets.cached()

      # Another node switches the active set
      Brando.Repo.update_all(Brando.Assets.SiteAssetSet, [set: [active: false]], prefix: "public")
      second |> Brando.Assets.SiteAssetSet.changeset(%{active: true}) |> Repo.update!()

      remote_refresh({SiteAssets, {:active, :standalone}})

      second_id = second.id
      assert %{set: %{id: ^second_id}} = SiteAssets.cached()
    end

    test "a preview another node pins drops this node's pinned listing" do
      assert SiteAssets.pinned_sets() == []
      assert :persistent_term.get({:brando, :site_assets, :pinned, :standalone}, :gone) == []

      remote_refresh({SiteAssets, {:pinned, :standalone}})

      assert :persistent_term.get({:brando, :site_assets, :pinned, :standalone}, :gone) == :gone
    end

    test "forgetting a set tells the other nodes" do
      {:ok, registered} = register_set("20260816_one")
      {:ok, _cached} = SiteAssets.set_cache(registered)

      SiteAssets.forget_set(registered)
      set_id = registered.id
      assert_received {:brando_cache_sync, _origin, {SiteAssets, {:set, ^set_id}}}
      assert_received {:brando_cache_sync, _origin, {SiteAssets, {:pinned, :standalone}}}

      {:ok, _cached} = SiteAssets.set_cache(registered)
      remote_refresh({SiteAssets, {:set, set_id}})
      assert :persistent_term.get({:brando, :site_assets, :set, set_id}, :gone) == :gone
    end
  end

  describe "the shared library" do
    test "a site's allowlist changed on another node is read again here" do
      site = insert_site!("acme")

      assert :ok = SharedLibrary.set_enabled(site, :module, [])
      site_id = site.id
      assert_received {:brando_cache_sync, _origin, {SharedLibrary.Cache, {^site_id, :module}}}

      # This node's copy, from before another node's change
      SharedLibrary.Cache.put(site.id, :module, [123])
      remote_refresh({SharedLibrary.Cache, {site.id, :module}})

      refute SharedLibrary.Cache.get(site.id, :module)
      assert SharedLibrary.enabled_ids(site, :module) == MapSet.new()
    end
  end

  defp send_remote(refresh) do
    Phoenix.PubSub.broadcast(Brando.pubsub(), CacheSync.topic(), {:brando_cache_sync, @other_node, refresh})
  end

  defp remote_refresh(refresh) do
    send_remote(refresh)
    CacheSync.sync()
  end

  defp eventually(fun, attempts \\ 50) do
    case fun.() do
      nil when attempts > 0 ->
        Process.sleep(20)
        eventually(fun, attempts - 1)

      result ->
        result
    end
  end

  defp register_set(name) do
    nil
    |> SiteAssetsFixtures.create_set(name, name, "#{name}.css")
    |> SiteAssets.register_set(%{})
  end

  defp site_attrs(key) do
    %{
      name: String.capitalize(key),
      key: key,
      languages: ["en"],
      default_language: "en",
      status: :active,
      delivery_mode: :dynamic
    }
  end

  defp insert_site!(key) do
    %Site{}
    |> Site.changeset(site_attrs(key))
    |> Repo.insert!()
  end

  defp insert_environment!(site, key, domain) do
    %Environment{}
    |> Environment.changeset(%{site_id: site.id, name: String.capitalize(key), key: key, live: true, domain: domain})
    |> Repo.insert!()
  end
end
