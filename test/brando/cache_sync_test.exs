defmodule Brando.CacheSyncTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import ExUnit.CaptureLog

  alias Brando.Assets.SiteAssets
  alias Brando.CacheSync
  alias Brando.Content.SharedLibrary
  alias Brando.Environments.Environment
  alias Brando.SiteAssetsFixtures
  alias Brando.Sites.Site
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry

  # One node in a test run: a refresh "from another node" is a message that
  # carries another node's origin.
  @other_node "another-node"

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
      assert origin == CacheSync.origin()

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
      remote_refresh(CacheSync.origin(), {Cache, :registry})

      assert Cache.get_env_by_domain("old.acme.test")
    end

    test "another server under the same node name is not taken for this one" do
      # Outside an Erlang cluster every server is nonode@nohost, and a PubSub
      # adapter such as Redis still carries their messages here
      site = insert_site!("acme")
      environment = insert_environment!(site, "production", "old.acme.test")
      Cache.warm()

      environment |> Environment.changeset(%{domain: "new.acme.test"}) |> Repo.update!()
      remote_refresh(node(), {Cache, :registry})

      refute Cache.get_env_by_domain("old.acme.test")
      assert Cache.get_env_by_domain("new.acme.test")
    end

    test "a warm that read the registry first cannot publish over a later one" do
      site = insert_site!("acme")
      environment = insert_environment!(site, "production", "old.acme.test")

      # Warming for another node's write, this node has read the registry...
      earlier = start_held("environments", &Cache.warm/0)

      # ...when a write here commits and warms
      environment |> Environment.changeset(%{domain: "new.acme.test"}) |> Repo.update!()
      later = Task.async(&Cache.warm/0)
      finished = Task.yield(later, 200)

      resume(earlier)
      assert :ok = Task.await(earlier)
      assert {:ok, :ok} = finished || Task.yield(later, 5_000)

      refute Cache.get_env_by_domain("old.acme.test")
      assert Cache.get_env_by_domain("new.acme.test")
    end

    test "without a PubSub, a broadcast held for the commit is dropped quietly" do
      # A mix task: `Brando.pubsub/0` names no running PubSub
      put_test_env(:app_module, Brando.CacheSyncTest.NoApp)

      log =
        capture_log(fn ->
          assert {:ok, :ok} = Brando.Repo.transaction(fn -> CacheSync.broadcast(Cache, :registry) end)
        end)

      refute log =~ "CacheSync"
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
      test = self()
      cache_sync = Process.whereis(CacheSync)
      on_query("sites", fn -> if self() == cache_sync, do: send(test, :warmed) end)

      # Held, the whole burst waits in the mailbox before the first is read,
      # so the debounce cannot end inside it
      :sys.suspend(CacheSync)
      for _ <- 1..25, do: send_remote({Cache, :registry})
      :sys.resume(CacheSync)
      CacheSync.sync()

      assert_received :warmed
      refute_received :warmed
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

    test "a fill that read the active set before another node changed it does not keep it" do
      {:ok, first} = register_set("20260816_one")
      {:ok, second} = register_set("20260816_two")
      {:ok, _active} = SiteAssets.activate_set(first.id)
      SiteAssets.invalidate_cache()

      # A request here has read the active set...
      fill = start_held("site_asset_sets", fn -> SiteAssets.cached() end)

      # ...when another node switches it, and this node hears of it
      Brando.Repo.update_all(Brando.Assets.SiteAssetSet, [set: [active: false]], prefix: "public")
      second |> Brando.Assets.SiteAssetSet.changeset(%{active: true}) |> Repo.update!()
      remote_refresh({SiteAssets, {:active, :standalone}})

      resume(fill)
      first_id = first.id
      assert %{set: %{id: ^first_id}} = Task.await(fill)

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

    test "a fill that read the allowlist before another node changed it does not keep it" do
      site = insert_site!("acme")
      user = Brando.Factory.insert(:random_user, role: :superuser)
      {:ok, module} = SharedLibrary.create_shared(:module, module_attrs(), user)
      assert :ok = SharedLibrary.set_enabled(site, :module, [module.id])
      SharedLibrary.Cache.invalidate(site.id, :module)

      # A request here has read the allowlist...
      fill = start_held("site_enabled_modules", fn -> SharedLibrary.enabled_ids(site, :module) end)

      # ...when another node empties it, and this node hears of it
      Repo.delete_all(Brando.Content.SiteEnabledModule, prefix: "public")
      remote_refresh({SharedLibrary.Cache, {site.id, :module}})

      resume(fill)
      assert Task.await(fill) == MapSet.new([module.id])

      assert SharedLibrary.enabled_ids(site, :module) == MapSet.new()
    end
  end

  defp send_remote(origin \\ @other_node, refresh) do
    Phoenix.PubSub.broadcast(Brando.pubsub(), CacheSync.topic(), {:brando_cache_sync, origin, refresh})
  end

  defp remote_refresh(origin \\ @other_node, refresh) do
    send_remote(origin, refresh)
    CacheSync.sync()
  end

  # Runs `fun` in a task held after its first query on `source`, until
  # `resume/1`: a cache fill caught between its read and its store.
  defp start_held(source, fun) do
    test = self()

    on_query(source, fn ->
      if Process.delete(:cache_sync_test_hold) do
        send(test, {:held, self()})

        receive do
          :resume -> :ok
        end
      end
    end)

    task =
      Task.async(fn ->
        Process.put(:cache_sync_test_hold, true)
        fun.()
      end)

    pid = task.pid
    assert_receive {:held, ^pid}, 5_000
    task
  end

  defp resume(%Task{pid: pid}), do: send(pid, :resume)

  # Runs `fun` in the querying process after each query on `source`
  defp on_query(source, fun) do
    id = make_ref()
    event = BrandoIntegration.Repo.config()[:telemetry_prefix] ++ [:query]
    :ok = :telemetry.attach(id, event, &__MODULE__.handle_query/4, {source, fun})
    on_exit(fn -> :telemetry.detach(id) end)
  end

  @doc false
  def handle_query(_event, _measurements, %{source: source}, {source, fun}), do: fun.()
  def handle_query(_event, _measurements, _metadata, _config), do: :ok

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

  defp module_attrs do
    %{
      name: %{"en" => "Hero"},
      namespace: %{"en" => "general"},
      help_text: %{"en" => "Help"},
      class: "module",
      code: "<section>Hero</section>"
    }
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
