Code.require_file("../../credo/checks/aliases.ex", __DIR__)
Code.require_file("../../credo/checks/test_sandbox_shared.ex", __DIR__)

defmodule Brando.Credo.Check.TestSandboxSharedTest do
  use Credo.Test.Case

  alias Brando.Credo.Check.TestSandboxShared

  setup_all do
    {:ok, _apps} = Application.ensure_all_started(:credo)
    :ok
  end

  defp issues(source, allowed \\ %{}, path \\ "test/sample_test.exs") do
    source
    |> to_source_file(path)
    |> run_check(TestSandboxShared, allowed: allowed)
  end

  test "flags shared mode and a shared owner, through aliases and pipes" do
    """
    defmodule SampleTest do
      alias Ecto.Adapters.SQL
      alias Ecto.Adapters.SQL.Sandbox, as: Box

      setup tags do
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
        Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
        SQL.Sandbox.start_owner!(Repo, shared: true)
        Box.start_owner!(Repo, shared: not tags[:async])
        Repo |> Box.mode({:shared, self()})
      end
    end
    """
    |> issues()
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &{&1.trigger, &1.line_no}) == [
               {"Ecto.Adapters.SQL.Sandbox.mode", 7},
               {"SQL.Sandbox.start_owner!", 8},
               {"Box.start_owner!", 9},
               {"Box.mode", 10}
             ]
    end)
  end

  test "leaves unshared sandboxes and other :shared values alone" do
    """
    defmodule SampleTest do
      alias Ecto.Adapters.SQL.Sandbox

      setup do
        pid = Sandbox.start_owner!(Repo)
        Sandbox.start_owner!(Repo, shared: false)
        Sandbox.mode(Repo, :manual)
        Sandbox.allow(Repo, pid, self())
        assert {:shared, 42} = SharedLibrary.reference("shared:42")
        Preview.render(entry, shared: true)
      end
    end
    """
    |> issues()
    |> refute_issues()
  end

  test "accepts an allowlisted file that gives a reason" do
    """
    defmodule SampleCase do
      def setup_sandbox(tags) do
        Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: not tags[:async])
      end
    end
    """
    |> issues(%{"test/support/sample_case.ex" => "LiveView processes"}, "test/support/sample_case.ex")
    |> refute_issues()
  end

  test "an allowlist entry needs a reason" do
    """
    defmodule SampleCase do
      def setup_sandbox, do: Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    end
    """
    |> issues(%{"test/support/sample_case.ex" => " "}, "test/support/sample_case.ex")
    |> assert_issue()
  end

  test "flags an allowlist entry whose file no longer uses shared mode" do
    """
    defmodule SampleCase do
      def setup_sandbox, do: Ecto.Adapters.SQL.Sandbox.start_owner!(Repo)
    end
    """
    |> issues(%{"test/support/sample_case.ex" => "LiveView processes"}, "test/support/sample_case.ex")
    |> assert_issue(fn issue -> assert issue.message =~ "remove it from `allowed`" end)
  end
end
