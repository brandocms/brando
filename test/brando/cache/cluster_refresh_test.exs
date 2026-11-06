defmodule Brando.Cache.ClusterRefreshTest do
  # Each node keeps its own site caches (identity, SEO, globals, palettes,
  # menus) and query cache. A save refreshes the node that ran it, and the
  # others through `Brando.CacheSync` once it has committed. One node in a
  # test run: a refresh "from another node" is a message that carries another
  # node's origin, and a row "another node wrote" is written with the repo.
  use Brando.ConnCase, async: false

  alias Brando.Authorization.{Boundary, Groups, Migration, Scope}
  alias Brando.Cache
  alias Brando.Cache.Freshness
  alias Brando.Cache.Query, as: QueryCache
  alias Brando.CacheSync
  alias Brando.Content.Module
  alias Brando.Content.RenderQueue
  alias Brando.{Factory, Repo}
  alias Brando.Navigation.Menu
  alias Brando.Pages.{Fragment, Page}
  alias Brando.Villain.ContextCache

  @other_node "another-node"
  # This node's record of the writes its render inputs have caught up with
  @tokens {Brando.Cache.Freshness, :tokens}

  setup do
    preserve_cache([:globals, :navigation, :palettes, :palettes_css, :identity, :seo, @tokens])
    preserve_query_cache([Page, Fragment, Module])
    Cache.Globals.set()
    Cache.Navigation.set()
    Cache.Palettes.set()
    Cache.Identity.set()
    Cache.SEO.set()
    CacheSync.sync()
    Phoenix.PubSub.subscribe(Brando.pubsub(), CacheSync.topic())
    on_exit(fn -> CacheSync.sync() end)
    %{user: Factory.insert(:random_user, role: :superuser)}
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

  describe "the site caches" do
    test "a save tells the other nodes once it has committed, and a rollback tells them nothing", c do
      assert {:ok, _} =
               Repo.transaction(fn ->
                 {:ok, set} = Brando.Sites.create_global_set(global_set("held", "Held", c.user), c.user)
                 refute_received {:brando_cache_sync, _, {Cache, _}}
                 set
               end)

      assert_received {:brando_cache_sync, origin, {Cache, {:globals, nil}}}
      assert origin == CacheSync.origin()

      assert {:error, :undone} =
               Repo.transaction(fn ->
                 {:ok, _} =
                   Brando.Navigation.create_menu(
                     %{status: :published, title: "M", key: "gone", language: "en", items: []},
                     c.user
                   )

                 Repo.rollback(:undone)
               end)

      refute_received {:brando_cache_sync, _, {Cache, _}}
    end

    test "a refresh from another node rebuilds each of this node's caches", c do
      {:ok, set} = Brando.Sites.create_global_set(global_set("system", "Old", c.user), c.user)

      {:ok, menu} =
        Brando.Navigation.create_menu(%{status: :published, title: "Old", key: "main", language: "en", items: []}, c.user)

      {:ok, palette} = Brando.Content.create_palette(palette("old"), c.user)
      {:ok, identity} = Brando.Sites.get_identity(%{matches: %{language: "en"}})
      {:ok, seo} = Brando.Sites.get_seo(%{matches: %{language: "en"}})

      # Another node saves them
      set.vars |> hd() |> Ecto.Changeset.change(value: "New") |> Repo.update!()
      menu |> Ecto.Changeset.change(title: "New") |> Repo.update!()
      palette |> Ecto.Changeset.change(key: "new") |> Repo.update!()
      identity |> Ecto.Changeset.change(name: "New name") |> Repo.update!()
      seo |> Ecto.Changeset.change(fallback_meta_title: "New title") |> Repo.update!()

      assert Brando.Sites.global("en", "system", "text").value == "Old"

      for cache <- [:globals, :navigation, :palettes, :identity, :seo], do: send_remote({Cache, {cache, nil}})
      CacheSync.sync()

      assert Brando.Sites.global("en", "system", "text").value == "New"
      assert Cache.Navigation.get("main", "en").title == "New"
      assert "new" in Enum.map(Cache.Palettes.get(), & &1.key)
      assert Phoenix.HTML.safe_to_string(Cache.Palettes.get_css()) =~ "site-new"
      assert Cache.Identity.get("en").name == "New name"
      assert Cache.SEO.get("en").fallback_meta_title == "New title"
    end

    test "this node's own messages are skipped: its caches are already fresh", c do
      {:ok, menu} =
        Brando.Navigation.create_menu(%{status: :published, title: "Old", key: "main", language: "en", items: []}, c.user)

      menu |> Ecto.Changeset.change(title: "New") |> Repo.update!()

      remote_refresh(CacheSync.origin(), {Cache, {:navigation, nil}})

      assert Cache.Navigation.get("main", "en").title == "Old"
    end

    test "a fill that read the database before another node's write cannot store over its rebuild", c do
      {:ok, menu} =
        Brando.Navigation.create_menu(%{status: :published, title: "Old", key: "main", language: "en", items: []}, c.user)

      # A request on this node fills the menus and has read them...
      earlier = start_held(Menu.__schema__(:source), &Cache.Navigation.set/0)

      # ...when another node's write commits and this node hears of it
      menu |> Ecto.Changeset.change(title: "New") |> Repo.update!()
      send_remote({Cache, {:navigation, nil}})
      refresh = Task.async(&CacheSync.sync/0)
      finished = Task.yield(refresh, 200)

      resume(earlier)
      Task.await(earlier)
      assert {:ok, :ok} = finished || Task.yield(refresh, 5_000)

      assert Cache.Navigation.get("main", "en").title == "New"
    end

    test "a rebuild that read the database before another's cannot store over it", c do
      {:ok, menu} =
        Brando.Navigation.create_menu(%{status: :published, title: "Old", key: "main", language: "en", items: []}, c.user)

      # This node rebuilds for one write and has read the menus...
      earlier = start_held(Menu.__schema__(:source), fn -> Cache.refresh_node_cache({:navigation, nil}) end)

      # ...when another write commits and its rebuild runs to the end
      menu |> Ecto.Changeset.change(title: "New") |> Repo.update!()
      later = Task.async(fn -> Cache.refresh_node_cache({:navigation, nil}) end)
      assert {:ok, :ok} = Task.yield(later, 2_000)

      resume(earlier)
      Task.await(earlier)

      assert Cache.Navigation.get("main", "en").title == "New"
    end

    test "fills and rebuilds do not wait for one another", c do
      {:ok, _menu} =
        Brando.Navigation.create_menu(%{status: :published, title: "Old", key: "main", language: "en", items: []}, c.user)

      Cache.del(:navigation)
      earlier = start_held(Menu.__schema__(:source), &Cache.Navigation.set/0)

      assert {:ok, {:ok, true}} = Task.yield(Task.async(&Cache.Navigation.set/0), 2_000)
      assert {:ok, :ok} = Task.yield(Task.async(fn -> Cache.refresh_node_cache({:navigation, nil}) end), 2_000)

      resume(earlier)
      Task.await(earlier)
    end

    test "a job's rebuild that loses the fence leaves the cache to fill, not as it was", c do
      {:ok, menu} =
        Brando.Navigation.create_menu(%{status: :published, title: "Old", key: "main", language: "en", items: []}, c.user)

      # Another node's write, which this node has not heard of
      menu |> Ecto.Changeset.change(title: "New") |> Repo.update!()

      # A render job carrying the write's token rebuilds, and has read the menus...
      args = %{"site_caches" => %{"navigation" => "another-node-token"}}
      job = start_held(Menu.__schema__(:source), fn -> Cache.ensure_fresh(args) end)

      # ...when this node's refresh for the same write begins, and reads too
      refresh = start_held(Menu.__schema__(:source), fn -> Cache.refresh_node_cache({:navigation, nil}) end)

      resume(job)
      assert Task.await(job) == :ok

      # The job renders next: from the write, not from what the cache held
      assert ContextCache.navigation()["main"]["en"].title == "New"
      assert Cache.Navigation.get("main", "en").title == "New"

      resume(refresh)
      Task.await(refresh)
    end

    test "a render reads the menus from the database when their cache is cold", c do
      {:ok, _menu} =
        Brando.Navigation.create_menu(%{status: :published, title: "Old", key: "main", language: "en", items: []}, c.user)

      Cache.del(:navigation)

      assert ContextCache.navigation()["main"]["en"].title == "Old"
      assert Cache.get(:navigation)["main"]["en"].title == "Old"
    end

    # The caches are every visitor's: an editor whose groups may not read
    # menus, global sets or identities opens a page while they are cold
    test "a cold fill under an admin's scope stores every visitor's rows, not what the admin may read", c do
      put_test_env(:authorization_mode, :groups, global: true)
      put_test_env(:tenancy_mode, :none, global: true)
      Boundary.put_scope(nil)
      {:ok, _} = Migration.run()

      {:ok, _} =
        Brando.Navigation.create_menu(
          %{status: :published, title: "Main", key: "main", language: "en", items: []},
          c.user
        )

      {:ok, _} = Brando.Sites.create_global_set(global_set("shown", "Shown", c.user), c.user)

      editor = Factory.insert(:random_user, role: :user)
      owner_scope = Scope.standalone(c.user)
      {:ok, group} = Groups.create(owner_scope, %{name: "Page editors"}, ~w(brando.admin.access brando.pages.read))
      {:ok, :ok} = Groups.add_member(owner_scope, group.id, editor.id)

      Cache.del(:navigation)
      Cache.del(:globals)
      Cache.del(:identity)

      Boundary.with_scope(Scope.standalone(editor), fn ->
        ContextCache.navigation()
        ContextCache.globals("en")
        ContextCache.identity("en")
      end)

      assert Cache.get(:navigation)["main"]["en"].title == "Main"
      assert Map.has_key?(Cache.get(:globals)["en"], "shown")
      assert %{language: :en} = Cache.get(:identity)["en"]
    end

    test "public's copy and the unprefixed one are one cache to the fence", c do
      {:ok, menu} =
        Brando.Navigation.create_menu(%{status: :published, title: "Old", key: "main", language: "en", items: []}, c.user)

      put_test_env(:tenancy_mode, :single, global: true)

      earlier =
        start_held(Menu.__schema__(:source), fn -> Brando.Tenant.with_public(&Cache.Navigation.set/0) end)

      menu |> Ecto.Changeset.change(title: "New") |> Repo.update!()
      later = Task.async(fn -> Cache.refresh_node_cache({:navigation, nil}) end)
      assert {:ok, :ok} = Task.yield(later, 2_000)

      resume(earlier)
      Task.await(earlier)

      assert Cache.Navigation.get("main", "en").title == "New"
    end
  end

  describe "rendering after a site cache's rebuild" do
    setup c do
      {:ok, module} =
        Brando.Content.create_module(
          Factory.params_for(:module, %{
            code: ~s(<div class="paragraph">Says: '{{ globals.system.text }}'. Name: '{{ identity.name }}'.</div>)
          }),
          :system
        )

      {:ok, fragment} =
        %Fragment{}
        |> Ecto.Changeset.change(
          Factory.params_for(:fragment, %{
            parent_key: "cluster",
            key: "cluster",
            entry_blocks: [
              %{block: %{type: :module, source: "Elixir.Brando.Pages.Fragment.Blocks", module_id: module.id, refs: []}}
            ]
          })
        )
        |> Brando.Pages.create_fragment(c.user)

      {:ok, set} = Brando.Sites.create_global_set(global_set("system", "Old", c.user), c.user)
      {:ok, _} = Brando.Content.Blocks.render_entry(Fragment, fragment.id)
      {:ok, identity} = Brando.Sites.get_identity(%{matches: %{language: "en"}})
      %{fragment: fragment, set: set, identity: identity}
    end

    test "a job run by a node that has not heard of the rebuild yet rebuilds its copy first", c do
      stale = Cache.get(:globals)
      jobs = update_text_queueing(c.set, "New", c.user)
      job = Enum.find(jobs, &(&1.args["entry_id"] == c.fragment.id))
      assert %{"globals" => _token} = job.args["site_caches"]

      # As on a node that has not heard: what its cache held before, and no
      # rebuild for this write
      Cache.put(:globals, stale, :infinite)
      Cache.del(@tokens)

      assert {:ok, _} = perform(job)
      assert Repo.get!(Fragment, c.fragment.id).rendered_blocks =~ "Says: 'New'."
      assert Brando.Sites.global("en", "system", "text").value == "New"
    end

    test "a node that has rebuilt for the write renders without rebuilding again", c do
      jobs = update_text_queueing(c.set, "New", c.user)
      job = Enum.find(jobs, &(&1.args["entry_id"] == c.fragment.id))

      # This node rebuilt when it saved; a marker shows whether it rebuilds again
      marker = put_in(Cache.get(:globals), ["en", "system", "text"], %{hd(c.set.vars) | value: "Marker"})
      Cache.put(:globals, marker, :infinite)

      assert {:ok, _} = perform(job)
      assert Repo.get!(Fragment, c.fragment.id).rendered_blocks =~ "Says: 'Marker'."
    end

    test "a render queued for any other reason carries this node's rebuilds too", c do
      update_text_queueing(c.set, "New", c.user)

      job =
        Oban.Testing.with_testing_mode(:manual, fn ->
          RenderQueue.enqueue(%{schema: Fragment, entry_id: c.fragment.id + 1_000_000})
        end)

      assert {:ok, %Oban.Job{args: %{"site_caches" => %{"globals" => _token}}}} = job
    end

    test "one transaction that changes identity and globals queues renders that need both", c do
      stale_globals = Cache.get(:globals)
      stale_identity = Cache.get(:identity)

      jobs =
        Oban.Testing.with_testing_mode(:manual, fn ->
          {:ok, _} =
            Repo.transaction(fn ->
              {:ok, _} = Brando.Sites.update_identity(c.identity.id, %{name: "New name"}, :system)
              vars = [%{type: "text", label: "Text", key: "text", value: "New", creator_id: c.user.id}]
              {:ok, _} = Brando.Sites.update_global_set(c.set.id, %{vars: vars}, :system)
            end)

          all_enqueued(worker: Brando.Worker.EntryRenderer)
        end)

      job = Enum.find(jobs, &(&1.args["entry_id"] == c.fragment.id))
      assert %{"identity" => _, "globals" => _} = job.args["site_caches"]

      Cache.put(:globals, stale_globals, :infinite)
      Cache.put(:identity, stale_identity, :infinite)
      Cache.del(@tokens)

      assert {:ok, _} = perform(job)
      assert Repo.get!(Fragment, c.fragment.id).rendered_blocks =~ "Says: 'New'. Name: 'New name'."
    end

    test "an entry saved after the change keeps what its render needs", c do
      jobs = update_text_queueing(c.set, "New", c.user)
      job = Enum.find(jobs, &(&1.args["entry_id"] == c.fragment.id))
      token = job.args["site_caches"]["globals"]

      # The same entry queued again before its render starts adds its tokens
      jobs =
        Oban.Testing.with_testing_mode(:manual, fn ->
          {:ok, _} = RenderQueue.enqueue(%{schema: Fragment, entry_id: c.fragment.id})
          all_enqueued(worker: Brando.Worker.EntryRenderer)
        end)

      replaced = Enum.find(jobs, &(&1.args["entry_id"] == c.fragment.id))
      assert %{"globals" => ^token} = replaced.args["site_caches"]
    end
  end

  describe "a rebuild that raises" do
    setup do
      put_test_env(:tenancy_mode, :multi, global: true)
      # A site whose schema is gone: every read of its tables raises
      prefix = "tenant_gone_production"
      keys = for key <- [@tokens, {Cache, :generation, :globals}], do: {:tenant, prefix, key}
      cached = for key <- keys, do: {key, Cachex.get!(:cache, key)}

      on_exit(fn ->
        for {key, value} <- cached,
            do: if(value, do: Cachex.put(:cache, key, value), else: Cachex.del(:cache, key))
      end)

      %{prefix: prefix}
    end

    test "leaves the render jobs it queues to rebuild on this node too", c do
      Brando.Tenant.with_prefix(c.prefix, fn ->
        assert_raise Postgrex.Error, fn -> in_savepoint(fn -> Cache.rebuild_after_commit(:globals) end) end

        args = Brando.Cache.Freshness.attach(%{})
        assert %{"globals" => _token} = args["site_caches"]

        # The job tries the rebuild again rather than render from the old copy
        assert_raise Postgrex.Error, fn -> in_savepoint(fn -> Cache.ensure_fresh(args) end) end
      end)
    end
  end

  describe "rendering after a module's change" do
    setup c do
      {:ok, module} =
        Brando.Content.create_module(
          Factory.params_for(:module, %{code: ~s(<div class="paragraph">Module: old.</div>)}),
          :system
        )

      {:ok, fragment} =
        %Fragment{}
        |> Ecto.Changeset.change(
          Factory.params_for(:fragment, %{
            parent_key: "module_change",
            key: "module_change",
            entry_blocks: [
              %{block: %{type: :module, source: "Elixir.Brando.Pages.Fragment.Blocks", module_id: module.id, refs: []}}
            ]
          })
        )
        |> Brando.Pages.create_fragment(c.user)

      {:ok, _} = Brando.Content.Blocks.render_entry(Fragment, fragment.id)
      %{module: module, fragment: fragment}
    end

    test "a job run by a node that has not evicted the modules evicts them first", c do
      jobs =
        Oban.Testing.with_testing_mode(:manual, fn ->
          {:ok, _} = Brando.Content.update_module(c.module.id, %{code: ~s(<div>Module: new.</div>)}, :system)
          all_enqueued(worker: Brando.Worker.EntryRenderer)
        end)

      job = Enum.find(jobs, &(&1.args["entry_id"] == c.fragment.id))
      source = Module.__schema__(:source)
      assert %{^source => _token} = job.args["query_sources"]

      # As on a node that has not heard: the module list cached before, and
      # no eviction for this write
      stale = {:list, source, "stale"}
      Cachex.put(:query, stale, [c.module])
      Cache.del(@tokens)

      assert {:ok, _} = perform(job)
      assert {:ok, nil} = Cachex.get(:query, stale)
      assert Repo.get!(Fragment, c.fragment.id).rendered_blocks =~ "Module: new."

      # Known now: the next job for the write evicts nothing
      Cachex.put(:query, stale, [c.module])
      assert {:ok, _} = perform(job)
      assert {:ok, [_]} = Cachex.get(:query, stale)
    end
  end

  describe "a module write in a transaction" do
    setup do
      {:ok, module} =
        Brando.Content.create_module(
          Factory.params_for(:module, %{code: ~s(<div class="paragraph">Module: old.</div>)}),
          :system
        )

      %{module: module, source: Module.__schema__(:source)}
    end

    test "carries its token in its own render jobs, and in other processes' only once committed", c do
      before = carried(c.source)

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, token} =
          Repo.transaction(fn ->
            {:ok, _} = Brando.Content.update_module(c.module.id, %{code: ~s(<div>Module: new.</div>)}, :system)
            token = carried(c.source)
            refute token == before

            # Another process on this node queues a render: the write has not committed
            assert run_elsewhere(fn -> carried(c.source) end) == before

            {:ok, job} = RenderQueue.enqueue(%{schema: Fragment, entry_id: 1_000_001})
            assert job.args["query_sources"][c.source] == token
            token
          end)

        assert carried(c.source) == token
        assert run_elsewhere(fn -> carried(c.source) end) == token
        assert Freshness.unknown(%{"query_sources" => %{c.source => token}}) == []
      end)
    end

    test "rolled back, its token is gone, and no later transaction of the process carries it", c do
      before = carried(c.source)

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:error, token} =
          Repo.transaction(fn ->
            {:ok, _} = Brando.Content.update_module(c.module.id, %{code: ~s(<div>Module: new.</div>)}, :system)
            Repo.rollback(carried(c.source))
          end)

        refute token == before
        assert carried(c.source) == before
        assert run_elsewhere(fn -> carried(c.source) end) == before
        assert {:ok, ^before} = Repo.transaction(fn -> carried(c.source) end)
      end)
    end

    test "makes one token however many times it writes the source", c do
      {:ok, {first, second}} =
        Repo.transaction(fn ->
          QueryCache.evict({:ok, c.module})
          first = carried(c.source)
          QueryCache.evict({:ok, c.module})
          {first, carried(c.source)}
        end)

      assert first == second
      assert carried(c.source) == first
      assert Freshness.unknown(%{"query_sources" => %{c.source => first}}) == []
    end
  end

  # The token for `source` a render job queued now would carry
  defp carried(source), do: Freshness.attach(%{})["query_sources"][source]

  defp run_elsewhere(fun), do: fun |> Task.async() |> Task.await()

  describe "the query cache" do
    test "a save tells the other nodes to evict its schema once committed, gathered" do
      page = Factory.insert(:page, title: "Before")
      source = Page.__schema__(:source)

      assert {:ok, _} =
               Repo.transaction(fn ->
                 {:ok, updated} = page |> Page.changeset(%{title: "After"}, :system) |> Brando.Query.update()
                 {:ok, _} = updated |> Page.changeset(%{title: "Again"}, :system) |> Brando.Query.update()
                 CacheSync.sync()
                 refute_received {:brando_cache_sync, _, _}
                 updated
               end)

      CacheSync.sync()
      assert_received {:brando_cache_sync, origin, {:batch, [{QueryCache, {nil, ^source}}]}}
      assert origin == CacheSync.origin()
      refute_received {:brando_cache_sync, _, _}
    end

    test "a burst of evictions goes out in a few bounded messages" do
      for _ <- 1..3, n <- 1..250, do: CacheSync.broadcast_gathered(QueryCache, {nil, "source_#{n}"})
      CacheSync.sync()

      batches = receive_batches()
      assert Enum.map(batches, &length/1) == [100, 100, 50]
      assert batches |> Enum.concat() |> Enum.uniq() |> length() == 250
    end

    test "an eviction from another node drops the schema's lists and entries under its site only" do
      put_test_env(:tenancy_mode, :multi, global: true)
      pages = Page.__schema__(:source)
      fragments = Fragment.__schema__(:source)
      prefix = "tenant_acme_production"

      keys = [
        {:list, pages, "a"},
        {:single, pages, "b", 1},
        {:list, fragments, "c"},
        {:tenant, prefix, {:list, pages, "d"}},
        {:tenant, prefix, {:single, pages, "e", 2}},
        {:tenant, "tenant_other_production", {:list, pages, "f"}}
      ]

      # `preserve_query_cache/1` in setup puts the sources' entries back
      for key <- keys, do: Cachex.put(:query, key, :cached)

      remote_refresh({:batch, [{QueryCache, {prefix, pages}}]})
      assert cached(keys) == [true, true, true, false, false, true]

      remote_refresh({:batch, [{QueryCache, {nil, pages}}, {:unknown, :refresh}]})
      assert cached(keys) == [false, false, true, false, false, true]
    end
  end

  defp cached(keys), do: Enum.map(keys, &match?({:ok, :cached}, Cachex.get(:query, &1)))

  defp receive_batches(acc \\ []) do
    receive do
      {:brando_cache_sync, _origin, {:batch, refreshes}} -> receive_batches([refreshes | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  # Saves the set's text with the render jobs queued, not run, and returns them
  defp update_text_queueing(set, value, user) do
    Oban.Testing.with_testing_mode(:manual, fn ->
      vars = [%{type: "text", label: "Text", key: "text", value: value, creator_id: user.id}]
      {:ok, _} = Brando.Sites.update_global_set(set.id, %{vars: vars}, :system)
      all_enqueued(worker: Brando.Worker.EntryRenderer)
    end)
  end

  defp perform(job), do: Brando.Worker.EntryRenderer.perform(job)

  # A transaction on the repo itself, so a query that fails leaves the test's
  # own usable, and `Brando.Repo.after_commit/2` runs its work at once
  defp in_savepoint(fun), do: BrandoIntegration.Repo.transaction(fun)

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
    id = make_ref()
    event = BrandoIntegration.Repo.config()[:telemetry_prefix] ++ [:query]
    :ok = :telemetry.attach(id, event, &__MODULE__.handle_query/4, {source, test})
    on_exit(fn -> :telemetry.detach(id) end)

    task =
      Task.async(fn ->
        Process.put(:cluster_refresh_test_hold, true)
        fun.()
      end)

    pid = task.pid
    assert_receive {:held, ^pid}, 5_000
    task
  end

  defp resume(%Task{pid: pid}), do: send(pid, :resume)

  @doc false
  def handle_query(_event, _measurements, %{source: source}, {source, test}) do
    if Process.delete(:cluster_refresh_test_hold) do
      send(test, {:held, self()})

      receive do
        :resume -> :ok
      end
    end
  end

  def handle_query(_event, _measurements, _metadata, _config), do: :ok
end
