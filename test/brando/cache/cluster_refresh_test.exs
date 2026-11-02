defmodule Brando.Cache.ClusterRefreshTest do
  # Each node keeps its own site caches (identity, SEO, globals, palettes,
  # menus) and query cache. A save refreshes the node that ran it, and the
  # others through `Brando.CacheSync` once it has committed. One node in a
  # test run: a refresh "from another node" is a message that carries another
  # node's origin, and a row "another node wrote" is written with the repo.
  use Brando.ConnCase, async: false

  alias Brando.Cache
  alias Brando.Cache.Query, as: QueryCache
  alias Brando.CacheSync
  alias Brando.{Factory, Repo}
  alias Brando.Navigation.Menu
  alias Brando.Pages.{Fragment, Page}

  @other_node "another-node"

  setup do
    preserve_cache([:globals, :navigation, :palettes, :palettes_css, :identity, :seo, {Cache, :fresh, :globals}])
    preserve_query_cache([Page, Fragment])
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
  end

  describe "rendering after a site cache's rebuild" do
    setup c do
      {:ok, module} =
        Brando.Content.create_module(
          Factory.params_for(:module, %{code: ~s(<div class="paragraph">Says: '{{ globals.system.text }}'.</div>)}),
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
      %{fragment: fragment, set: set}
    end

    test "a job run by a node that has not heard of the rebuild yet rebuilds its copy first", c do
      stale = Cache.get(:globals)
      jobs = update_text_queueing(c.set, "New", c.user)
      job = Enum.find(jobs, &(&1.args["entry_id"] == c.fragment.id))
      assert %{"globals" => _token} = job.args["site_caches"]

      # As on a node that has not heard: what its cache held before, and no
      # rebuild for this write
      Cache.put(:globals, stale, :infinite)
      Cache.del({Cache, :fresh, :globals})

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

    test "a render queued for any other reason carries no site caches", c do
      job =
        Oban.Testing.with_testing_mode(:manual, fn ->
          Brando.Content.RenderQueue.enqueue(%{schema: Fragment, entry_id: c.fragment.id})
        end)

      assert {:ok, %Oban.Job{args: args}} = job
      refute Map.has_key?(args, "site_caches")
    end
  end

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
      put_test_env(:tenancy_mode, :multi)
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

      for key <- keys, do: Cachex.put(:query, key, :cached)
      on_exit(fn -> for key <- keys, do: Cachex.del(:query, key) end)

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
