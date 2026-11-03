defmodule Brando.Content.RenderQueueTest do
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.RenderQueue
  alias Brando.Factory
  alias Brando.Pages.Fragment
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
