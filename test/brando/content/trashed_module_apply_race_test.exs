defmodule Brando.Content.TrashedModuleApplyRaceTest do
  # A definition apply that changes a module against an editor's save that
  # adds a block of it, each on its own connection (#3902). The save's
  # trashed-module check share-locks the module's row; it must queue behind
  # a running apply before it does, or the apply, waiting to update that
  # row, and the save, waiting to write its vars, deadlock. The sandbox
  # shares one connection between processes, so the rows are committed, and
  # every row the test adds is deleted after it.
  use ExUnit.Case, async: false

  @moduletag :capture_log

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.{Block, Definitions, Var}
  alias Brando.Pages.Page
  alias Brando.ProposalFixtures
  alias Ecto.Adapters.SQL.Sandbox

  @repo Brando.Repo.repo()

  setup do
    before = last_ids()
    path = Path.join(System.tmp_dir!(), "brando-trashed-module-apply-#{System.unique_integer([:positive])}")

    on_exit(fn ->
      File.rm_rf!(path)
      delete_since!(before)
    end)

    {user, module, page, plan} = unboxed(fn -> fixture!(path) end)
    %{user: user, module: module, page: page, plan: plan}
  end

  test "a save that adds a block while the apply holds its locks waits for it, and both land", c do
    apply = paused(fn -> Definitions.apply(c.plan, c.user) end, &(&1.query =~ "LOCK TABLE"))
    save = reporting(fn -> add_block(c.page, c.module, c.user) end)

    await_blocked!()
    send(apply.pid, :go)

    assert {:ok, _} = Task.await(apply, 30_000)
    assert {:ok, _} = Task.await(save, 30_000)
    assert block_count(c.module) == 1
  end

  test "an apply that starts while a save checks the module waits for it, and both land", c do
    save = paused(fn -> add_block(c.page, c.module, c.user) end, &(&1.query =~ "FOR SHARE"))
    apply = reporting(fn -> Definitions.apply(c.plan, c.user) end)

    await_blocked!()
    send(save.pid, :go)

    assert {:ok, _} = Task.await(save, 30_000)
    assert {:ok, _} = Task.await(apply, 30_000)
    assert block_count(c.module) == 1
  end

  # Runs `fun` on a connection of its own and stops it after the first query
  # `pause?` matches, until told to go on
  defp paused(fun, pause?) do
    test = self()
    handler = "trashed-module-apply-#{System.unique_integer([:positive])}"
    task = Task.async(fn -> receive(do: (:start -> unboxed(fun))) end)

    :telemetry.attach(
      handler,
      @repo.config()[:telemetry_prefix] ++ [:query],
      fn _event, _measurements, metadata, pid ->
        if self() == pid and pause?.(metadata) do
          :telemetry.detach(handler)
          send(test, :paused)
          receive(do: (:go -> :ok))
        end
      end,
      task.pid
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    send(task.pid, :start)
    assert_receive :paused, 10_000
    task
  end

  # The form's save adding one root block of `module`, with its var
  defp add_block(page, module, user) do
    block = %{
      type: :module,
      module_id: module.id,
      source: to_string(Page.Blocks),
      uid: Brando.Utils.generate_uid(),
      vars: [%Var{type: :string, key: "tagline", label: %{"en" => "Tagline"}, value: "Added"}]
    }

    page
    |> @repo.preload(:entry_blocks, force: true)
    |> Page.changeset(%{}, user)
    |> Ecto.Changeset.put_assoc(:entry_blocks, [%{block: block}])
    |> Brando.Pages.update_page(user)
  end

  # A module with a var, whose file changes its code, and a page without blocks
  defp fixture!(path) do
    user = Brando.Factory.insert(:random_user)

    module =
      ProposalFixtures.module!(user, "Racer", "<p>{{ tagline }}</p>",
        vars: [%{type: "string", key: "tagline", label: "Tagline", value: "Default tagline"}]
      )

    page = Brando.Factory.insert(:page, creator: user, title: "Race", uri: "race-#{System.unique_integer([:positive])}")

    {:ok, _} = Definitions.export(path, user, uids: [module.uid])
    liquid = Path.join(path, "content/racer.liquid")
    File.write!(liquid, String.replace(File.read!(liquid), "<p>{{ tagline }}</p>", "<div>{{ tagline }}</div>"))

    {:ok, bundle} = Definitions.read(path)
    {:ok, plan} = Definitions.plan(bundle, user)
    {user, module, page, plan}
  end

  defp block_count(module),
    do: unboxed(fn -> @repo.aggregate(from(b in Block, where: b.module_id == ^module.id), :count) end)

  defp unboxed(fun), do: Sandbox.unboxed_run(@repo, fun)

  # Runs `fun` on a connection of its own, which it reports to the test
  defp reporting(fun) do
    test = self()

    Task.async(fn ->
      unboxed(fn ->
        send(test, {:backend, backend_pid()})
        fun.()
      end)
    end)
  end

  defp backend_pid, do: hd(hd(@repo.query!("SELECT pg_backend_pid()").rows))

  # Until Postgres reports the second connection waiting for another's lock
  defp await_blocked! do
    assert_receive {:backend, pid}, 10_000
    await_blocked!(pid, 500)
  end

  defp await_blocked!(pid, tries) do
    blocked? = unboxed(fn -> hd(hd(@repo.query!("SELECT pg_blocking_pids($1) <> '{}'", [pid]).rows)) end)

    cond do
      blocked? -> :ok
      tries == 0 -> flunk("the second connection never waited for the first")
      true -> Process.sleep(20) && await_blocked!(pid, tries - 1)
    end
  end

  # The last id of each table
  defp last_ids do
    unboxed(fn ->
      "SELECT table_name FROM information_schema.columns WHERE table_schema = 'public' AND column_name = 'id' AND data_type IN ('bigint', 'integer')"
      |> @repo.query!()
      |> Map.fetch!(:rows)
      |> List.flatten()
      |> Map.new(fn table -> {table, hd(hd(@repo.query!(~s|SELECT coalesce(max(id), 0) FROM "#{table}"|).rows))} end)
    end)
  end

  # Every row added since `before`; foreign keys aside, as rows reference
  # each other in every direction
  defp delete_since!(before), do: unboxed(fn -> @repo.transaction(fn -> delete_rows!(before) end) end)

  defp delete_rows!(before) do
    @repo.query!("SET LOCAL session_replication_role = replica")
    @repo.query!("DELETE FROM revisions WHERE entry_type = $1 AND entry_id > $2", [to_string(Page), before["pages"]])
    for {table, id} <- before, do: @repo.query!(~s(DELETE FROM "#{table}" WHERE id > $1), [id])
  end
end
