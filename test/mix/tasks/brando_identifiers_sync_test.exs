defmodule Mix.Tasks.Brando.Identifiers.SyncTest do
  use Brando.ConnCase

  import ExUnit.CaptureIO

  alias Mix.Tasks.Brando.Identifiers.Sync

  # Swaps the global `Mix.shell()`; Brando.ConnCase runs synchronously.
  setup do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(shell) end)

    Mix.Task.reenable("brando.identifiers.sync")
    Mix.Task.reenable("run")
    :ok
  end

  test "--yes is accepted, as the other derived-data tasks take it" do
    # Some test Blueprints' identifiers raise, so the sync itself may exit 1;
    # what matters is that it got past the options.
    capture_io(fn ->
      try do
        Sync.run(["--yes"])
      catch
        :exit, {:shutdown, 1} -> :ok
      end
    end)

    assert_received {:mix_shell, :info, [header]}
    assert header =~ "% Brando Sync Identifiers"
    assert_received {:mix_shell, :info, ["Servers that were already running keep serving what they cached before." <> _]}
  end

  test "an unknown option stops the task and names the options it takes" do
    assert_raise Mix.Error,
                 "mix brando.identifiers.sync: unknown or invalid option --all. It takes: --yes, --force",
                 fn ->
                   Sync.run(["--all"])
                 end
  end

  test "a positional argument stops the task" do
    assert_raise Mix.Error, ~r/unexpected argument MyApp.Projects.Project/, fn ->
      Sync.run(["MyApp.Projects.Project"])
    end
  end
end
