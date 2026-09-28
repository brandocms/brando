# Load with elixir -r scripts/test_timings.exs -S mix test --formatter
# ExUnit.CLIFormatter --formatter Brando.TestTimingsFormatter.
# Unlike --slowest, this does not enable trace mode or serialize async tests.
defmodule Brando.TestTimingsFormatter do
  use GenServer

  def init(_opts), do: {:ok, []}

  def handle_cast({:test_finished, test}, tests), do: {:noreply, [test | tests]}

  def handle_cast({:suite_finished, timing}, tests) do
    modules =
      tests
      |> Enum.group_by(& &1.module)
      |> Enum.map(fn {module, tests} ->
        %{
          module: inspect(module),
          file: Path.relative_to_cwd(hd(tests).tags.file),
          async: hd(tests).tags.async,
          tests: length(tests),
          seconds: Enum.reduce(tests, 0, &((&1.time || 0) + &2)) / 1_000_000
        }
      end)
      |> Enum.sort_by(& &1.seconds, :desc)

    path = System.get_env("BRANDO_TEST_TIMINGS", "tmp/test-timings.json")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(%{timing: timing, modules: modules}, pretty: true))
    {:noreply, tests}
  end

  def handle_cast(_event, tests), do: {:noreply, tests}
end
