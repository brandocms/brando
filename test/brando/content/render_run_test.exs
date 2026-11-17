defmodule Brando.Content.RenderRunTest do
  @moduledoc """
  Following the render jobs a definition import or refresh queued, wherever
  they run (brandocms/brando#3611). Oban runs `:manual` here, so the jobs
  wait as rows until the test drains them, as a server or the task's own
  queue would run them.
  """
  use ExUnit.Case, async: false

  @moduletag :capture_log
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.{Definitions, RenderQueue}
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.Repo

  setup do
    Brando.ProposalFixtures.context()
  end

  defp manual(fun), do: Oban.Testing.with_testing_mode(:manual, fun)

  defp refresh!(c) do
    {{:ok, [%{status: :requested}]}, run} =
      Definitions.track_refresh(fn -> Definitions.refresh([c.text_module.uid], c.user) end)

    run
  end

  defp jobs(worker \\ Brando.Worker.EntryRenderer),
    do: Repo.all(from(j in Oban.Job, where: j.worker == ^inspect(worker), order_by: j.id))

  test "follows the renders a refresh queued until they complete", c do
    manual(fn ->
      run = refresh!(c)
      assert [_, _] = jobs()

      assert %{rendered: 0, failed: [], pending: [_, _], timed_out: true} = Definitions.await_refresh(run, timeout: 0)
      Oban.drain_queue(queue: :default)

      assert %{rendered: 2, failed: [], pending: [], timed_out: false} = Definitions.await_refresh(run, timeout: 0)
      assert Repo.get!(Page, c.identity.id).rendered_blocks =~ "<p>"
    end)
  end

  test "names a render that failed, with its error" do
    manual(fn ->
      {_, run} = Definitions.track_refresh(fn -> RenderQueue.enqueue(%{schema: Page, entry_id: -1}) end)
      Oban.drain_queue(queue: :default)

      assert %{rendered: 0, pending: [], timed_out: false, failed: [failure]} =
               Definitions.await_refresh(run, timeout: 1_000)

      assert %{worker: :render, schema: "Brando.Pages.Page", entry_id: -1, state: "retryable"} = failure
      assert is_binary(failure.error)
    end)
  end

  test "times out naming the renders still waiting, and reports progress", c do
    manual(fn ->
      run = refresh!(c)
      parent = self()

      result = Definitions.await_refresh(run, timeout: 30, interval: 10, on_progress: &send(parent, {:progress, &1}))

      assert %{rendered: 0, failed: [], timed_out: true, pending: pending} = result
      ids = [c.identity.id, c.naming.id]
      assert Enum.sort(Enum.map(pending, & &1.entry_id)) == Enum.sort(ids)
      assert Enum.all?(pending, &(&1.schema == "Brando.Pages.Page" and &1.state == "available"))
      assert_received {:progress, %{done: 0, total: 2, failed: 0}}
    end)
  end

  test "leaves jobs another run or a save queued out of it", c do
    manual(fn ->
      other = Factory.insert(:page, creator: c.user)
      RenderQueue.enqueue(%{schema: Page, entry_id: other.id})
      run = refresh!(c)
      {_, other_run} = Definitions.track_refresh(fn -> RenderQueue.enqueue(%{schema: Page, entry_id: other.id}) end)

      ids = for job <- jobs(), job.args["entry_id"] in [c.identity.id, c.naming.id], do: job.id
      Repo.update_all(from(j in Oban.Job, where: j.id in ^ids), set: [state: "completed"])

      assert %{rendered: 2, pending: [], timed_out: false} = Definitions.await_refresh(run, timeout: 0)
      assert %{rendered: 0, pending: [%{entry_id: id}]} = Definitions.refresh_status(other_run)
      assert id == other.id
    end)
  end

  # Renders of an entry queued within seconds of each other coalesce
  # (`RenderQueue.enqueue/2`): the run follows the one that renders for it
  test "follows a render it coalesced into", c do
    manual(fn ->
      RenderQueue.enqueue(%{schema: Page, entry_id: c.identity.id})
      run = refresh!(c)
      assert [_, _] = jobs()
      assert %{pending: [_, _]} = Definitions.refresh_status(run)
    end)
  end

  # The render of a fragment queues the entries that embed it, and a cascade
  # the entries that list the one saved: the run follows those too
  test "a job of the run marks the jobs it queues", c do
    manual(fn ->
      {_, run} = Definitions.track_refresh(fn -> RenderQueue.enqueue(%{schema: Page, entry_id: c.identity.id}) end)
      [job] = jobs()

      Brando.Content.RenderRun.within(job, fn -> RenderQueue.enqueue(%{schema: Page, entry_id: c.naming.id}) end)

      assert %{pending: [_, _]} = Definitions.refresh_status(run)
    end)
  end

  test "counts a cascade the run queued, and its failure", c do
    manual(fn ->
      {_, run} =
        Definitions.track_refresh(fn -> Brando.Content.Blocks.enqueue_entry_cascade(Page, c.identity, nil) end)

      assert [_] = jobs(Brando.Worker.EntryCascade)
      assert %{pending: [%{worker: :cascade, entry_id: id}]} = Definitions.refresh_status(run)
      assert id == c.identity.id
    end)
  end

  test "a run with nothing queued is done at once" do
    assert {:done, run} = Definitions.track_refresh(fn -> :done end)
    assert %{rendered: 0, failed: [], pending: [], timed_out: false} = Definitions.await_refresh(run)
  end
end
