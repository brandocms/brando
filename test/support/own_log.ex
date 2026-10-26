defmodule Brando.Test.OwnLog do
  @moduledoc """
  What the calling process logs while `fun` runs, for tests that assert on it.

  `ExUnit.CaptureLog` captures through one `:logger` handler shared by every
  test. It formats each event in a task it waits five seconds for; when that
  wait fails under load, `:logger` removes the handler, and every capture open
  at the time returns `""` (the run's output shows
  `{removed_failing_handler,'Elixir.ExUnit.CaptureServer'}`). An async test
  asserting on its log then fails for another test's event.

  `capture/1` adds a handler of its own for the events of the calling
  process and the tasks it starts, which formats them in place and sends them
  to that process, so nothing another test logs can take it away. It runs
  inside `capture_log/1`, which keeps the output off the console.
  """

  @spec capture((-> any())) :: String.t()
  def capture(fun) do
    id = :"#{__MODULE__}.#{System.unique_integer([:positive])}"
    ref = make_ref()
    :ok = :logger.add_handler(id, __MODULE__, %{config: %{pid: self(), ref: ref}})

    try do
      ExUnit.CaptureLog.capture_log(fun)
    after
      :logger.remove_handler(id)
    end

    ref |> collect([]) |> IO.chardata_to_string()
  end

  # The handler runs in the logging process, so every event logged before
  # `fun` returned (a task's: before it was awaited) is in the mailbox
  defp collect(ref, acc) do
    receive do
      {^ref, chardata} -> collect(ref, [acc, chardata])
    after
      0 -> acc
    end
  end

  # Runs in the logging process: the caller's own events, and those of the
  # tasks it started (whose `$callers` name it), so a `refute` still holds
  # when the logging moves into one
  @doc false
  def log(%{meta: %{pid: pid}} = event, %{config: %{pid: caller, ref: ref}}) do
    if pid == caller or caller in Process.get(:"$callers", []) do
      {formatter, config} = Logger.default_formatter(colors: [enabled: false])
      send(caller, {ref, formatter.format(event, config)})
    end

    :ok
  end
end
