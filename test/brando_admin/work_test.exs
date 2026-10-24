defmodule BrandoAdmin.WorkTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias BrandoAdmin.Work
  alias Phoenix.Socket.Broadcast

  defmodule DoneWorker do
    @moduledoc false
    use Oban.Worker, queue: :default, max_attempts: 1

    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"result" => "ok"}}), do: :ok
    def perform(%Oban.Job{args: %{"result" => "error"}}), do: {:error, :nope}
    def perform(%Oban.Job{args: %{"result" => "cancel"}}), do: {:cancel, :not_now}
  end

  setup do
    # Ids no other test reports for, so nothing leaks between tests
    user_id = System.unique_integer([:positive])
    Work.subscribe(user_id)
    %{user_id: user_id}
  end

  test "work is reported, remembered while it runs and forgotten when it ends", %{user_id: user_id} do
    Brando.endpoint().subscribe("user:#{user_id}")
    on_exit(fn -> Brando.endpoint().unsubscribe("user:#{user_id}") end)

    Work.start(user_id, "fetch", "Fetching")
    assert_receive {:work, "fetch", :running, %Work{message: "Fetching", started_at: started_at}}
    assert %Work{status: :running, message: "Fetching"} = Work.get(user_id, "fetch")
    assert [%Work{key: "fetch"}] = Work.list(user_id)

    assert_receive %Broadcast{event: "work", payload: %{id: "fetch", status: :running, message: "Fetching"}}

    Work.update(user_id, "fetch", "Fetched 3 of 5", percent: 60)
    assert_receive {:work, "fetch", :running, %Work{message: "Fetched 3 of 5", percent: 60, started_at: ^started_at}}

    # No new message keeps the last one
    Work.update(user_id, "fetch", nil, percent: 80)
    assert_receive {:work, "fetch", :running, %Work{message: "Fetched 3 of 5", percent: 80}}

    Work.finish(user_id, "fetch", "Fetched")
    assert_receive {:work, "fetch", :finished, %Work{message: "Fetched", percent: nil}}
    assert_receive %Broadcast{event: "work", payload: %{status: :finished, message: "Fetched"}}, 500
    assert Work.get(user_id, "fetch") == nil
    assert Work.list(user_id) == []
  end

  test "a failure ends the work with its message", %{user_id: user_id} do
    Work.start(user_id, "fetch", "Fetching")
    Work.fail(user_id, "fetch", "Could not fetch")
    assert_receive {:work, "fetch", :failed, %Work{message: "Could not fetch"}}
    assert Work.get(user_id, "fetch") == nil
  end

  test "an update for work it does not know starts it", %{user_id: user_id} do
    Work.update(user_id, "late", "Halfway", percent: 50)
    assert_receive {:work, "late", :running, %Work{message: "Halfway", percent: 50}}
  end

  test "steps count up to the total, and a failed step fails the work", %{user_id: user_id} do
    Work.start(user_id, "batch", "Writing", total: 2, done: "All written", failed: "Some failed")
    assert_receive {:work, "batch", :running, %Work{total: 2, done: 0}}

    # A second batch while the first runs joins its count
    Work.start(user_id, "batch", "Writing", total: 1)
    assert_receive {:work, "batch", :running, %Work{total: 3, done_message: "All written"}}

    Work.advance(user_id, "batch")
    assert_receive {:work, "batch", :running, %Work{done: 1} = work}
    assert Work.percent(work) == 33

    Work.advance(user_id, "batch")
    assert_receive {:work, "batch", :running, %Work{done: 2}}

    Work.advance(user_id, "batch", :error)
    assert_receive {:work, "batch", :failed, %Work{done: 3, failed: 1, message: "Some failed"}}

    # Steps of work that ended change nothing
    Work.advance(user_id, "batch")
    refute_receive {:work, "batch", _, _}, 100
  end

  test "steps that all succeed finish the work", %{user_id: user_id} do
    Work.start(user_id, "batch", "Writing", total: 1, done: "All written")
    Work.advance(user_id, "batch")
    assert_receive {:work, "batch", :finished, %Work{message: "All written"}}
  end

  test "work without news is given up", %{user_id: user_id} do
    Work.start(user_id, "slow", "Working", timeout: 50)
    assert_receive {:work, "slow", :running, _}
    assert_receive {:work, "slow", :failed, %Work{timed_out: true} = work}, 1000
    assert Work.to_payload(work).message == nil
    assert Work.fallback_message(work) == "Stopped reporting progress"
    assert Work.get(user_id, "slow") == nil
  end

  test "news keeps work from timing out", %{user_id: user_id} do
    Work.start(user_id, "slow", "Working", timeout: 150)
    Process.sleep(100)
    Work.update(user_id, "slow", "Still working")
    assert_receive {:work, "slow", :running, %Work{message: "Still working"}}
    refute_receive {:work, "slow", :failed, _}, 100
    Work.finish(user_id, "slow")
    assert_receive {:work, "slow", :finished, %Work{message: nil} = work}
    assert Work.fallback_message(work) == "Done"
  end

  test "work for the system reports nowhere" do
    assert Work.start(:system, "fetch", "Fetching") == :ok
    assert Work.start(nil, "fetch", "Fetching") == :ok
    assert Work.list(:system) == []
  end

  test "the payload is JSON, with a percent from the count", %{user_id: user_id} do
    Work.start(user_id, "batch", "Writing", total: 4)
    Work.advance(user_id, "batch")
    assert_receive {:work, "batch", :running, %Work{done: 1} = work}

    assert %{"id" => "batch", "status" => "running", "percent" => 25, "done" => 1, "total" => 4, "toast" => "auto"} =
             work |> Work.to_payload() |> Jason.encode!() |> Jason.decode!()
  end

  describe "tracked Oban jobs" do
    test "report their start and outcome", %{user_id: user_id} do
      %{"result" => "ok"}
      |> DoneWorker.new()
      |> Work.track(user_id, "job", running: "Running", done: "Ran")
      |> Oban.insert!()

      assert_receive {:work, "job", :running, %Work{message: "Running"}}
      assert_receive {:work, "job", :finished, %Work{message: "Ran"}}
    end

    test "report a failure and a cancellation as failed", %{user_id: user_id} do
      for {result, key} <- [{"error", "error-job"}, {"cancel", "cancel-job"}] do
        %{"result" => result}
        |> DoneWorker.new()
        |> Work.track(user_id, key, running: "Running", failed: "Gave up")
        |> Oban.insert!()

        assert_receive {:work, ^key, :failed, %Work{message: "Gave up"}}
      end
    end

    test "a job queued to run now starts its work when inserted", %{user_id: user_id} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        job =
          %{"result" => "ok"}
          |> DoneWorker.new()
          |> Work.track(user_id, "queued-job", queued: "Waiting", running: "Running")
          |> Oban.insert!()

        assert_receive {:work, "queued-job", :running, %Work{message: "Waiting"}}

        # A scheduled one does not
        %{"result" => "ok"}
        |> DoneWorker.new(schedule_in: 600)
        |> Work.track(user_id, "scheduled-job", running: "Running")
        |> Oban.insert!()

        refute_receive {:work, "scheduled-job", _, _}, 100

        Brando.Repo.delete_all(Oban.Job)
        job
      end)
    end

    test "step jobs count towards their work", %{user_id: user_id} do
      Work.start(user_id, "steps", "Writing", total: 2, done: "Written", failed: "Some failed")

      for result <- ["ok", "error"] do
        %{"result" => result}
        |> DoneWorker.new()
        |> Work.track(user_id, "steps", step: true)
        |> Oban.insert!()
      end

      assert_receive {:work, "steps", :running, %Work{done: 1}}
      assert_receive {:work, "steps", :failed, %Work{done: 2, failed: 1, message: "Some failed"}}
    end

    test "a job tracked for the system is left as it is" do
      changeset = DoneWorker.new(%{"result" => "ok"})
      assert Work.track(changeset, :system, "job") == changeset
    end
  end
end
