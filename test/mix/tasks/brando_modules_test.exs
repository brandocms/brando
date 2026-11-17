defmodule Mix.Tasks.Brando.ModulesTest do
  @moduledoc """
  `mix brando.modules refresh` waits for the renders it queued, or leaves them
  for a running server with `--no-wait` (brandocms/brando#3611). Oban runs
  `:manual` here: a drainer process stands in for the queue that runs them.
  """
  use ExUnit.Case, async: false

  @moduletag :capture_log
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Definition.Watcher
  alias Brando.Repo
  alias Mix.Tasks.Brando.Modules

  setup do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(shell) end)
    Brando.ProposalFixtures.context()
  end

  defp refresh(c, extra \\ []) do
    args = ["refresh", "--uid", c.text_module.uid, "--user", to_string(c.user.id)] ++ extra
    Oban.Testing.with_testing_mode(:manual, fn -> Modules.run(args) end)
  end

  defp output do
    receive do
      {:mix_shell, _level, [line]} -> [line | output()]
    after
      0 -> []
    end
  end

  # Runs the default queue until stopped, each time `ready?` says so
  defp drainer(ready? \\ fn -> true end) do
    Task.async(fn -> drain(ready?) end)
  end

  defp drain(ready?) do
    if ready?.(), do: Oban.Testing.with_testing_mode(:manual, fn -> Oban.drain_queue(queue: :default) end)

    receive do
      :stop -> :ok
    after
      10 -> drain(ready?)
    end
  end

  defp stop(task) do
    send(task.pid, :stop)
    Task.await(task)
  end

  defp states, do: Repo.all(from(j in Oban.Job, select: j.state, order_by: j.id))

  test "refresh waits until the entries it queued have rendered", c do
    task = drainer()
    refresh(c)
    stop(task)

    assert states() == ["completed", "completed"]
    assert Enum.any?(output(), &(&1 =~ "Rendered 2 entries"))
  end

  test "refresh exits non-zero naming the entries whose render failed", c do
    # Points the run's renders at an entry that is gone, and runs them
    task =
      drainer(fn ->
        {count, _} =
          Repo.update_all(from(j in Oban.Job, where: j.state == "available"),
            set: [args: %{"schema" => "Brando.Pages.Page", "entry_id" => -1}]
          )

        count > 0
      end)

    error = assert_raise Mix.Error, fn -> refresh(c) end
    stop(task)

    assert error.message =~ "failed to render"
    assert Enum.any?(output(), &(&1 =~ "Brando.Pages.Page #-1"))
  end

  test "refresh exits non-zero when the timeout passes, naming the entries left", c do
    error = assert_raise Mix.Error, fn -> refresh(c, ["--timeout", "0"]) end
    assert error.message =~ "Timed out"
    lines = output()
    assert Enum.any?(lines, &(&1 =~ "Brando.Pages.Page ##{c.identity.id}"))
    assert Enum.any?(lines, &(&1 =~ "Brando.Pages.Page ##{c.naming.id}"))
    assert states() == ["available", "available"]
  end

  test "--no-wait leaves the renders queued for the running server", c do
    refresh(c, ["--no-wait"])

    assert states() == ["available", "available"]
    assert Enum.any?(output(), &(&1 =~ "2 entry renders are queued"))
  end

  describe "the application the task starts" do
    setup do
      oban = Application.get_env(:brando, Oban)
      watcher = Application.get_env(:brando, Watcher)

      on_exit(fn ->
        Application.put_env(:brando, Oban, oban)
        if watcher, do: Application.put_env(:brando, Watcher, watcher), else: Application.delete_env(:brando, Watcher)
      end)

      Application.put_env(:brando, Watcher, path: "priv/modules", user_id: 1)
      Application.put_env(:brando, Oban, Keyword.put(oban, :queues, default: 4, mailers: 2))
    end

    test "runs no definition watcher" do
      Modules.configure_start(true)
      assert Watcher.children() == []
    end

    test "runs only the render queue when it waits" do
      Modules.configure_start(true)
      assert Application.get_env(:brando, Oban)[:queues] == [default: 4]
    end

    # Stopping, it lets a render it has started run to its timeout
    test "gives a render it runs the time to finish when it stops" do
      Modules.configure_start(true)
      grace = Application.get_env(:brando, Oban)[:shutdown_grace_period]
      assert is_integer(grace) and grace > :timer.seconds(30)
    end

    test "fetches no jobs with --no-wait" do
      Modules.configure_start(false)
      assert Application.get_env(:brando, Oban)[:queues] == false
    end
  end
end
