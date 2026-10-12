defmodule Mix.Tasks.Brando.Entries.ResaveTest do
  use Brando.ConnCase

  alias Mix.Tasks.Brando.Entries.Resave

  # Swaps the global `Mix.shell()`; Brando.ConnCase runs synchronously.
  setup do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(shell) end)

    Mix.Task.reenable("brando.entries.resave")
    Mix.Task.reenable("run")
    :ok
  end

  test "with nobody to answer the prompt, it does nothing and fails" do
    send(self(), {:mix_shell_input, :prompt, :eof})

    assert_raise Mix.Error, ~r/stdin is closed, so nothing was done. Pass --yes/, fn -> Resave.run([]) end
    refute_received {:mix_shell, :info, ["\n==> Done.\n"]}
  end

  test "answering no says nothing was done" do
    send(self(), {:mix_shell_input, :prompt, "n"})

    Resave.run([])

    assert_received {:mix_shell, :info, ["Nothing was done."]}
  end

  test "--yes is accepted" do
    Resave.run(["--yes", "Brando.Pages.Fragment"])

    assert_received {:mix_shell, :info, ["\n==> Done.\n"]}
  end

  test "an unknown option or a second Blueprint stops the task" do
    assert_raise Mix.Error, ~r/unknown or invalid option --all. It takes: --yes, --force/, fn -> Resave.run(["--all"]) end

    assert_raise Mix.Error, ~r/unexpected argument Brando.Pages.Fragment Brando.Pages.Page/, fn ->
      Resave.run(["Brando.Pages.Fragment", "Brando.Pages.Page"])
    end
  end

  describe "Mix.Brando.confirm?/2" do
    test "--yes and --force answer without asking" do
      assert Mix.Brando.confirm?("Proceed?", yes: true)
      assert Mix.Brando.confirm?("Proceed?", force: true)
      refute_received {:mix_shell, :prompt, _}
    end

    test "an empty answer or y is yes, anything else no" do
      for {answer, expected} <- [{"", true}, {"y", true}, {"Yes\n", true}, {"n", false}, {"nope", false}] do
        send(self(), {:mix_shell_input, :prompt, answer})
        assert Mix.Brando.confirm?("Proceed?") == expected
      end
    end
  end
end
