defmodule Mix.Tasks.Brando.DoctorTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.DoctorFixtures.{Fails, Healthy, Warns}
  alias Mix.Tasks.Brando.Doctor, as: Task

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  # Only the given checks: Brando's own depend on the test application's state
  defp only(checks), do: put_test_env(Brando.Doctor, checks: checks, skip: Brando.Doctor.default_checks())

  defp output do
    receive do
      {:mix_shell, :info, [text]} -> text
    after
      0 -> flunk("no output")
    end
  end

  test "prints the report and exits 0 with only warnings" do
    only([Healthy, Warns])

    assert Task.run([]) == nil
    text = output()
    assert text =~ "✓ Healthy"
    assert text =~ "! Warns"
    assert text =~ "1 warning."
  end

  test "--strict fails on warnings" do
    only([Healthy, Warns])
    assert catch_exit(Task.run(["--strict"])) == {:shutdown, 1}
  end

  test "an error exits 1" do
    only([Healthy, Fails])
    assert catch_exit(Task.run([])) == {:shutdown, 1}
    assert output() =~ "✗ Fails"
  end

  test "--json prints machine output" do
    only([Healthy, Warns])
    Task.run(["--json"])

    assert %{"status" => "warning", "checks" => [%{"id" => "healthy"}, %{"id" => "warns", "items" => ["a", "b"]}]} =
             Jason.decode!(output())
  end

  test "--verbose lists the items" do
    only([Warns])
    Task.run(["--verbose"])
    assert output() =~ "· b"
  end

  test "a custom check registered through config runs after Brando's" do
    put_test_env(Brando.Doctor, checks: [Healthy])

    try do
      Task.run(["--json"])
    catch
      # The test application has no sitemap; the exit status is not the point
      :exit, {:shutdown, 1} -> :ok
    end

    ids = output() |> Jason.decode!() |> Map.fetch!("checks") |> Enum.map(& &1["id"])
    assert hd(ids) == "versions"
    assert List.last(ids) == "healthy"
  end
end
