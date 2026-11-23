defmodule Brando.Content.RenderQueueTest do
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.RenderQueue
  alias Brando.Content.RenderRun
  alias Brando.Factory
  alias Brando.Pages.Fragment
  alias Brando.Pages.Page
  alias Brando.Repo
  alias Brando.Worker.EntryRenderer

  test "enqueue/1 targets the entry renderer without executing it inline" do
    assert {:ok, job} =
             Oban.Testing.with_testing_mode(:manual, fn ->
               RenderQueue.enqueue(%{schema: Brando.Pages.Page, entry_id: 12_345})
             end)

    assert job.worker == "Brando.Worker.EntryRenderer"
    # With this node's render input tokens, if it has any (`Brando.Cache.Freshness`)
    assert %{entry_id: 12_345, schema: Brando.Pages.Page} = job.args
    assert job.tags == ["render_entry"]
  end

  describe "an entry queued again" do
    setup do
      user = Factory.insert(:random_user, role: :superuser)

      {:ok, module} =
        Brando.Content.create_module(
          Factory.params_for(:module, %{code: ~s(<div class="paragraph">Module: one.</div>)}),
          :system
        )

      {:ok, fragment} =
        %Fragment{}
        |> Ecto.Changeset.change(
          Factory.params_for(:fragment, %{
            parent_key: "requeue",
            key: "requeue",
            entry_blocks: [
              %{block: %{type: :module, source: "Elixir.Brando.Pages.Fragment.Blocks", module_id: module.id, refs: []}}
            ]
          })
        )
        |> Brando.Pages.create_fragment(user)

      {:ok, _} = Brando.Content.Blocks.render_entry(Fragment, fragment.id)
      %{module: module, fragment: fragment}
    end

    test "while its render runs renders once more after it, with the later write", c do
      Oban.Testing.with_testing_mode(:manual, fn ->
        save_module(c.module, "two")
        assert [job] = renders(c.fragment)

        # The job has read the entry and the module, and not stored yet
        running = start_held(job)
        save_module(c.module, "three")
        assert [next] = renders(c.fragment)

        # Run on another node, it waits: it would store before the first
        assert {:snooze, _} = EntryRenderer.perform(next)

        resume(running)
        assert {:ok, _} = Task.await(running)
        finish(job)
        assert rendered(c.fragment) =~ "Module: two."

        assert {:ok, _} = EntryRenderer.perform(next)
      end)

      assert rendered(c.fragment) =~ "Module: three."
    end

    test "waits for one that started first, though queued after it", c do
      Oban.Testing.with_testing_mode(:manual, fn ->
        # Queued in a transaction that commits after another node's render
        # of the entry was queued and started: a lower id, started later
        save_module(c.module, "two")
        assert [first] = renders(c.fragment)
        {:ok, started} = RenderQueue.coalesce({:ok, %Oban.Job{conflict?: true, id: nil}}, render_changeset(c), & &1)
        assert started.id > first.id
        set_job(started, state: "executing", attempt: 1, meta: started_at(-1))
        set_job(first, state: "executing", attempt: 1)

        assert {:snooze, _} = EntryRenderer.perform(Repo.get!(Oban.Job, first.id))
        set_job(first, state: "scheduled")
        assert {:ok, _} = EntryRenderer.perform(Repo.get!(Oban.Job, started.id))
      end)
    end

    test "waits for one that started first, though Oban stamped this one's attempt earlier", c do
      Oban.Testing.with_testing_mode(:manual, fn ->
        save_module(c.module, "two")
        assert [running] = renders(c.fragment)
        {:ok, next} = RenderQueue.coalesce({:ok, %Oban.Job{conflict?: true, id: nil}}, render_changeset(c), & &1)

        # The producer that took `next` read the time, then waited for a
        # connection while `running` was taken and started
        set_job(running, state: "executing", attempt: 1, meta: started_at(-1))
        set_job(next, state: "executing", attempt: 1, attempted_at: DateTime.add(DateTime.utc_now(), -10))

        assert {:snooze, _} = EntryRenderer.perform(Repo.get!(Oban.Job, next.id))
      end)
    end

    test "that waits takes the tokens of the one it waits for", c do
      Oban.Testing.with_testing_mode(:manual, fn ->
        save_module(c.module, "two")
        assert [running] = renders(c.fragment)
        {:ok, next} = RenderQueue.coalesce({:ok, %Oban.Job{conflict?: true, id: nil}}, render_changeset(c), & &1)

        # Queued on another node, after a write this one may not have heard of
        tokens = %{"globals" => "their-token"}
        meta = started_at(-1)

        Repo.update_all(from(j in Oban.Job, where: j.id == ^running.id),
          set: [args: Map.put(running.args, "site_caches", tokens)]
        )

        set_job(running, state: "executing", attempt: 1, meta: meta)

        assert {:snooze, _} = EntryRenderer.perform(Repo.get!(Oban.Job, next.id))
        assert %{"globals" => "their-token"} = Repo.get!(Oban.Job, next.id).args["site_caches"]
      end)
    end

    test "does not wait for a stamp an earlier attempt left", c do
      Oban.Testing.with_testing_mode(:manual, fn ->
        save_module(c.module, "two")
        assert [retried] = renders(c.fragment)
        {:ok, next} = RenderQueue.coalesce({:ok, %Oban.Job{conflict?: true, id: nil}}, render_changeset(c), & &1)

        # Taken again for its retry, and not stamped yet: the stamp is its
        # first attempt's
        meta = Map.put(started_at(-20), "render_attempted_at", "2026-01-01 00:00:00")
        set_job(retried, state: "executing", attempt: 2, attempted_at: DateTime.utc_now(), meta: meta)

        assert {:ok, _} = EntryRenderer.perform(Repo.get!(Oban.Job, next.id))
      end)
    end

    test "run without a job row renders", c do
      assert {:ok, _} = perform_job(EntryRenderer, %{schema: Fragment, entry_id: c.fragment.id})
    end

    test "while a render left running by a node that went down renders without waiting", c do
      Oban.Testing.with_testing_mode(:manual, fn ->
        save_module(c.module, "two")
        assert [job] = renders(c.fragment)
        set_job(job, state: "executing", attempt: 1, meta: started_at(-60))

        save_module(c.module, "three")
        assert [next] = renders(c.fragment)
        assert {:ok, _} = EntryRenderer.perform(next)
      end)

      assert rendered(c.fragment) =~ "Module: three."
    end

    test "while its render waits to retry renders now, with every attempt", c do
      Oban.Testing.with_testing_mode(:manual, fn ->
        save_module(c.module, "two")
        assert [job] = renders(c.fragment)
        in_future = DateTime.add(DateTime.utc_now(), 60)
        set_job(job, state: "retryable", attempt: 1, attempted_at: DateTime.utc_now(), scheduled_at: in_future)

        save_module(c.module, "three")

        assert [next] = renders(c.fragment)
        assert next.id != job.id
        assert next.attempt == 0
        assert {:ok, _} = EntryRenderer.perform(next)
      end)

      assert rendered(c.fragment) =~ "Module: three."
    end

    test "before its render starts coalesces into it, with every write's tokens", c do
      source = Brando.Content.Module.__schema__(:source)

      Oban.Testing.with_testing_mode(:manual, fn ->
        for code <- ~w(two three four), do: save_module(c.module, code)

        assert [job] = renders(c.fragment)
        assert [_, _, _] = Enum.uniq(job.args["query_sources"][source])
        assert {:ok, _} = EntryRenderer.perform(job)
      end)

      assert rendered(c.fragment) =~ "Module: four."
    end
  end

  describe "a conflict" do
    setup do
      preserve_cache([:globals, {Brando.Cache.Freshness, :tokens}])
    end

    test "with a job another transaction is inserting queues this one too" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        changeset = EntryRenderer.new(%{schema: Fragment, entry_id: 12_345})

        assert {:ok, %Oban.Job{id: id}} =
                 RenderQueue.coalesce({:ok, %Oban.Job{conflict?: true, id: nil}}, changeset, &Map.merge/2)

        assert is_integer(id)
        assert [%{id: ^id}] = all_enqueued(worker: EntryRenderer, args: %{entry_id: 12_345})
      end)
    end

    test "with a job that has started since queues this one after it" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, job} = RenderQueue.enqueue(%{schema: Fragment, entry_id: 12_345})
        set_job(job, state: "executing", attempt: 1, attempted_at: DateTime.utc_now())
        changeset = EntryRenderer.new(%{schema: Fragment, entry_id: 12_345})
        found = Repo.get!(Oban.Job, job.id)

        assert {:ok, %Oban.Job{id: id}} =
                 RenderQueue.coalesce({:ok, %{found | conflict?: true, state: "available"}}, changeset, &Map.merge/2)

        assert id != job.id
        assert [%{id: ^id}] = all_enqueued(worker: EntryRenderer, args: %{entry_id: 12_345})
      end)
    end

    test "keeps the tokens another node's render carries" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        # Queued by another node, which had rebuilt the globals for a write
        {:ok, theirs} =
          %{schema: Fragment, entry_id: 12_345, site_caches: %{"globals" => "their-token"}}
          |> Brando.Tenant.Job.attach()
          |> EntryRenderer.new()
          |> Oban.insert()

        # This node rebuilds its globals for a write of its own
        Brando.Cache.rebuild_after_commit(:globals)

        assert {:ok, %{id: id}} = RenderQueue.enqueue(%{schema: Fragment, entry_id: 12_345})
        assert id == theirs.id
        assert [job] = all_enqueued(worker: EntryRenderer, args: %{entry_id: 12_345})
        assert %{"globals" => ["their-token", ours]} = job.args["site_caches"]
        assert is_binary(ours)
        # A node that runs it refreshes for either, this one for theirs
        assert [{{:site_cache, :globals}, "their-token"}] = Brando.Cache.Freshness.unknown(job.args)
      end)
    end
  end

  describe "tokens" do
    test "past the most one job carries for an input, its renders refresh the input whatever they know" do
      tokens = for n <- 1..17, do: "token-#{n}"

      args =
        Enum.reduce(tokens, %{}, fn token, args ->
          Brando.Cache.Freshness.merge(args, %{"site_caches" => %{"globals" => token}})
        end)

      assert %{"site_caches" => %{"globals" => any}} = args
      assert [{{:site_cache, :globals}, ^any}] = Brando.Cache.Freshness.unknown(args)
      Brando.Cache.Freshness.known({:site_cache, :globals}, any)
      assert [{{:site_cache, :globals}, ^any}] = Brando.Cache.Freshness.unknown(args)
      # And stays so as more coalesce into it
      assert ^args = Brando.Cache.Freshness.merge(args, %{"site_caches" => %{"globals" => "token-18"}})
    end
  end

  describe "bulk renders" do
    setup do
      preserve_cache([:globals, {Brando.Cache.Freshness, :tokens}])
    end

    @tag :capture_log
    test "an editor's render queued after 500 bulk renders runs before them" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        bulk = RenderQueue.enqueue_many(Page, Enum.to_list(1_000_001..1_000_500))
        assert length(bulk) == 500
        {:ok, editor} = RenderQueue.enqueue(%{schema: Page, entry_id: 2_000_000})

        # The queue's producer takes one at a time (`limit: 1`)
        Oban.drain_queue(queue: :default, with_limit: 1)

        assert Repo.get!(Oban.Job, editor.id).state != "available"
        assert Repo.aggregate(from(j in Oban.Job, where: j.state == "available"), :count) == 500
      end)
    end

    test "for an entry with a render waiting adds no job, whatever its age, and keeps the tokens and runs of both" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        # Queued long ago by another node, for its own run
        {_, their_run} =
          RenderRun.track(fn ->
            %{schema: Fragment, entry_id: 12_345, site_caches: %{"globals" => "their-token"}}
            |> Brando.Tenant.Job.attach()
            |> EntryRenderer.new()
            |> RenderRun.tag()
            |> Oban.insert()
          end)

        [theirs] = all_enqueued(worker: EntryRenderer, args: %{entry_id: 12_345})
        set_job(theirs, inserted_at: hours_ago(1), scheduled_at: hours_ago(1))

        # This node rebuilds its globals for a write of its own
        Brando.Cache.rebuild_after_commit(:globals)
        {[{:ok, merged}], our_run} = RenderRun.track(fn -> RenderQueue.enqueue_map(%{Fragment => [12_345, 12_345]}) end)

        assert merged.id == theirs.id
        assert [job] = all_enqueued(worker: EntryRenderer, args: %{entry_id: 12_345})
        assert %{"globals" => ["their-token", ours]} = job.args["site_caches"]
        assert is_binary(ours)
        assert Enum.sort(job.meta["brando_runs"]) == Enum.sort([their_run, our_run])
      end)
    end

    test "deduplicate the set and insert the others in the bulk lane" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        result = RenderQueue.enqueue_map(%{Fragment => [1, 2, 2], "Elixir.Brando.Pages.Fragment" => [1, 3]})

        assert [_, _, _] = result
        jobs = all_enqueued(worker: EntryRenderer)
        assert Enum.sort(Enum.map(jobs, & &1.args["entry_id"])) == [1, 2, 3]
        assert Enum.all?(jobs, &(&1.priority == RenderQueue.bulk_priority() and &1.state == "available"))
        assert Enum.all?(jobs, &(&1.tags == ["render_entry"]))
      end)
    end

    test "an interactive render merging into a bulk one moves it to the front" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        [{:ok, bulk}] = RenderQueue.enqueue_many(Fragment, [12_345])
        set_job(bulk, inserted_at: hours_ago(1))

        assert {:ok, %{id: id}} = RenderQueue.enqueue(%{schema: Fragment, entry_id: 12_345})
        assert id == bulk.id
        assert [%{priority: 0, state: "available"}] = all_enqueued(worker: EntryRenderer)
      end)
    end

    test "an interactive render merging into a held one makes it run now, first" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        [{:ok, held}] = RenderQueue.enqueue_map(%{Fragment => [12_345]}, hold: "run-1")
        set_job(held, inserted_at: hours_ago(1))

        assert {:ok, %{id: id}} = RenderQueue.enqueue(%{schema: Fragment, entry_id: 12_345})
        assert id == held.id
        assert [job] = all_enqueued(worker: EntryRenderer)
        assert %{priority: 0, state: "available"} = job
        assert DateTime.compare(job.scheduled_at, DateTime.utc_now()) != :gt
      end)
    end

    test "held renders merge, and release together" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        held = RenderQueue.enqueue_map(%{Fragment => [1, 2]}, hold: "run-1")
        assert Enum.all?(held, fn {:ok, job} -> job.state == "scheduled" end)
        for {:ok, job} <- held, do: set_job(job, inserted_at: hours_ago(1))

        # A later step of the run, another run that holds
        RenderQueue.enqueue_map(%{Fragment => [1]}, hold: "run-1")
        RenderQueue.enqueue_map(%{Fragment => [2]}, hold: "run-2")
        RenderQueue.enqueue_map(%{Fragment => [3]}, hold: "run-2")

        assert [%{state: "scheduled"}, %{state: "scheduled"}, %{state: "scheduled"}] = renders_by_entry()
        assert RenderQueue.release("run-1") == 2
        assert [%{state: "available"}, %{state: "available"}, %{state: "scheduled"}] = renders_by_entry()
        assert RenderQueue.release("run-1") == 0
        assert RenderQueue.release("run-2") == 1
        assert Enum.all?(renders_by_entry(), &(&1.state == "available"))
      end)
    end

    test "a request that does not hold makes a held render it merges into run now, in the bulk lane" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        [{:ok, held}] = RenderQueue.enqueue_map(%{Fragment => [12_345]}, hold: "run-1")

        assert [{:ok, %{id: id, state: "available"}}] = RenderQueue.enqueue_map(%{Fragment => [12_345]})
        assert id == held.id
        assert [job] = all_enqueued(worker: EntryRenderer)
        assert %{state: "available", priority: 5} = job
        assert DateTime.compare(job.scheduled_at, DateTime.utc_now()) != :gt

        # A later request that holds leaves it running now
        RenderQueue.enqueue_map(%{Fragment => [12_345]}, hold: "run-2")
        assert [%{state: "available"}] = all_enqueued(worker: EntryRenderer)
      end)
    end

    test "held renders release in the site that holds them" do
      put_test_env(:tenancy_mode, :multi)

      Oban.Testing.with_testing_mode(:manual, fn ->
        for prefix <- ~w(tenant_one_live tenant_two_live) do
          Brando.Tenant.with_prefix(prefix, fn -> RenderQueue.enqueue_map(%{Fragment => [1]}, hold: "run") end)
        end

        assert Brando.Tenant.with_prefix("tenant_one_live", fn -> RenderQueue.release("run") end) == 1
        states = Map.new(renders_by_entry(), &{&1.args["tenant_prefix"], &1.state})
        assert states == %{"tenant_one_live" => "available", "tenant_two_live" => "scheduled"}
      end)
    end

    test "a bulk request merges into the waiting render of its own site only" do
      put_test_env(:tenancy_mode, :multi)

      Oban.Testing.with_testing_mode(:manual, fn ->
        for prefix <- ~w(tenant_one_live tenant_two_live tenant_one_live) do
          Brando.Tenant.with_prefix(prefix, fn -> RenderQueue.enqueue_map(%{Fragment => [1]}) end)
        end

        prefixes = Enum.map(all_enqueued(worker: EntryRenderer), & &1.args["tenant_prefix"])
        assert Enum.sort(prefixes) == ~w(tenant_one_live tenant_two_live)
      end)
    end

    test "a bulk request without a site merges into the waiting render without one only" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        RenderQueue.enqueue_map(%{Fragment => [1]})

        put_test_env(:tenancy_mode, :multi)
        Brando.Tenant.with_prefix("tenant_one_live", fn -> RenderQueue.enqueue_map(%{Fragment => [1]}) end)

        put_test_env(:tenancy_mode, :none)
        RenderQueue.enqueue_map(%{Fragment => [1]})

        prefixes = Enum.map(all_enqueued(worker: EntryRenderer), & &1.args["tenant_prefix"])
        assert Enum.sort(prefixes) == [nil, "tenant_one_live"]
      end)
    end

    # A named statement switches to a generic plan after five runs on a
    # connection, which joins thousands of keys in a nested loop
    test "looks up the waiting renders with an unnamed statement, planned for its keys" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        for n <- 1..6, do: RenderQueue.enqueue_many(Fragment, [n])

        %{rows: [[named]]} =
          Ecto.Adapters.SQL.query!(
            Repo.repo(),
            "SELECT count(*) FROM pg_prepared_statements WHERE statement LIKE '%unnest($1::text[], $2::text[], $3::text[])%'"
          )

        assert named == 0
      end)
    end

    @tag :capture_log
    test "held renders run by themselves after the maximum hold" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        RenderQueue.enqueue_map(%{Fragment => [1, 2]}, hold: "a-run-that-died")
        max_hold = RenderQueue.max_hold()
        assert max_hold == :timer.minutes(15)

        Oban.drain_queue(
          queue: :default,
          with_scheduled: DateTime.add(DateTime.utc_now(), max_hold - 60_000, :millisecond)
        )

        assert Enum.all?(renders_by_entry(), &(&1.state == "scheduled"))

        Oban.drain_queue(
          queue: :default,
          with_scheduled: DateTime.add(DateTime.utc_now(), max_hold + 1_000, :millisecond)
        )

        assert [] = all_enqueued(worker: EntryRenderer)
      end)
    end

    test "for N entries makes the same number of queries" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        queries = fn ids ->
          # Half of them have a render waiting
          RenderQueue.enqueue_many(Fragment, Enum.take_every(ids, 2))
          count_queries(fn -> RenderQueue.enqueue_many(Fragment, ids) end)
        end

        few = queries.(Enum.to_list(1..4))
        assert few > 0
        assert queries.(Enum.to_list(101..300)) == few
      end)
    end

    test "past the most parameters one statement takes, queue them all, held or not, and merge into them" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        ids = Enum.to_list(1..7_000)

        assert length(RenderQueue.enqueue_many(Page, ids)) == 7_000
        assert length(RenderQueue.enqueue_many(Fragment, ids, hold: "run-1")) == 7_000
        # Each merges into the one waiting
        assert length(RenderQueue.enqueue_many(Page, ids, hold: "run-1")) == 7_000

        assert Repo.aggregate(from(j in Oban.Job, where: j.state == "available"), :count) == 7_000
        assert Repo.aggregate(from(j in Oban.Job, where: j.state == "scheduled"), :count) == 7_000
        assert RenderQueue.release("run-1") == 7_000
      end)
    end

    test "counts its renders as steps of work" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        user = Factory.insert(:random_user)
        :ok = Phoenix.PubSub.subscribe(Brando.pubsub(), BrandoAdmin.Work.topic())

        # One waits for other work, and counts at once
        {:ok, _} =
          %{schema: Fragment, entry_id: 1}
          |> EntryRenderer.new()
          |> BrandoAdmin.Work.track(user, "other", step: true)
          |> Oban.insert()

        RenderQueue.enqueue_many(Fragment, [1, 2, 3], work: {user, "renders", message: "Updating pages"})

        assert_received {:brando_work, {:start, {_, _, "renders"}, %{total: 3, message: "Updating pages"}, _}}
        assert_received {:brando_work, {:advance, {_, _, "renders"}, %{result: :ok}, _}}

        tracked = for job <- renders_by_entry(), do: job.meta["brando_work"]["key"]
        assert tracked == ["other", "renders", "renders"]
      end)
    end

    test "requested twice for the same work counts it twice, once as soon as it merges" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        user = Factory.insert(:random_user)
        :ok = Phoenix.PubSub.subscribe(Brando.pubsub(), BrandoAdmin.Work.topic())

        for _ <- 1..2, do: RenderQueue.enqueue_many(Fragment, [1], hold: "run", work: {user, "refresh"})

        assert [job] = renders_by_entry()
        assert job.meta["brando_work"]["step"]
        total = receive_work(:start, 0, &(&1 + &2.total))
        # The job reports one step when it runs, the rest have been reported
        assert receive_work(:advance, 0, fn n, _ -> n + 1 end) + 1 == total
      end)
    end
  end

  describe "an entry's cascade queued again" do
    test "before it starts coalesces into it, and after it has started runs after it" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        entry = %Brando.Pages.Page{id: 12_345}
        {:ok, job} = Brando.Content.Blocks.enqueue_entry_cascade(Brando.Pages.Page, entry, nil)
        {:ok, _} = Brando.Content.Blocks.enqueue_entry_cascade(Brando.Pages.Page, entry, 7)
        assert [%{id: id, args: %{"identifier_id" => 7}}] = cascades(entry)
        assert id == job.id

        # It may have listed the entries to render before this write
        set_job(job, state: "executing", attempt: 1, attempted_at: DateTime.utc_now())
        {:ok, _} = Brando.Content.Blocks.enqueue_entry_cascade(Brando.Pages.Page, entry, 7)
        assert [%{id: next}] = cascades(entry)
        assert next != job.id
      end)
    end
  end

  defp receive_work(event, acc, fun) do
    receive do
      {:brando_work, {^event, {_, _, "refresh"}, attrs, _}} -> receive_work(event, fun.(acc, attrs), fun)
    after
      0 -> acc
    end
  end

  defp renders_by_entry, do: Enum.sort_by(all_enqueued(worker: EntryRenderer), & &1.args["entry_id"])

  defp hours_ago(hours), do: DateTime.add(DateTime.utc_now(), -hours * 3600)

  defp count_queries(fun) do
    handler = "render-queue-#{System.unique_integer([:positive])}"
    event = Repo.repo().config()[:telemetry_prefix] ++ [:query]
    test = self()
    :ok = :telemetry.attach(handler, event, fn _, _, _, _ -> if self() == test, do: send(test, :query) end, nil)

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end

    count_received(0)
  end

  defp count_received(n) do
    receive do
      :query -> count_received(n + 1)
    after
      0 -> n
    end
  end

  defp cascades(entry), do: all_enqueued(worker: Brando.Worker.EntryCascade, args: %{entry_id: entry.id})

  defp save_module(module, code) do
    {:ok, _} =
      Brando.Content.update_module(module.id, %{code: ~s(<div class="paragraph">Module: #{code}.</div>)}, :system)
  end

  defp render_changeset(c), do: EntryRenderer.new(%{schema: Fragment, entry_id: c.fragment.id})

  defp renders(fragment), do: all_enqueued(worker: EntryRenderer, args: %{entry_id: fragment.id})

  defp rendered(fragment), do: Repo.get!(Fragment, fragment.id).rendered_blocks

  # As the queue's producer does when it takes the job
  defp set_job(job, fields), do: Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id), set: fields)

  # As a render stamps its start (`EntryRenderer`), `seconds` from now
  defp started_at(seconds), do: %{"render_started" => System.os_time(:microsecond) + seconds * 1_000_000}

  defp finish(job), do: set_job(job, state: "completed", completed_at: DateTime.utc_now())

  # Runs `job` as the producer would, held once it has rendered and before it
  # stores, until `resume/1`
  defp start_held(job) do
    test = self()
    id = make_ref()
    :ok = :telemetry.attach(id, [:brando, :villain, :parse_and_render], &__MODULE__.handle_render/4, test)
    on_exit(fn -> :telemetry.detach(id) end)
    set_job(job, state: "executing", attempt: 1, attempted_at: DateTime.utc_now())

    task =
      Task.async(fn ->
        Process.put(:render_queue_test_hold, true)
        EntryRenderer.perform(%{job | state: "executing", attempt: 1})
      end)

    pid = task.pid
    assert_receive {:held, ^pid}, 5_000
    task
  end

  defp resume(%Task{pid: pid}), do: send(pid, :resume)

  @doc false
  def handle_render(_event, _measurements, _metadata, test) do
    if Process.delete(:render_queue_test_hold) do
      send(test, {:held, self()})

      receive do
        :resume -> :ok
      end
    end
  end
end
