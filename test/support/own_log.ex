defmodule Brando.Test.OwnLog do
  @moduledoc """
  What the calling process logs while `fun` runs, for tests that assert on it.

  `ExUnit.CaptureLog` captures through one `:logger` handler shared by every
  test. It formats each event in a task it waits five seconds for; when that
  wait fails under load, `:logger` removes the handler, and every capture open
  at the time returns `""` (the run's output shows
  `{removed_failing_handler,'Elixir.ExUnit.CaptureServer'}`). An async test
  asserting on its log then fails for another test's event.

  `capture/1` adds a handler of its own for the calling process's events,
  which formats them in place and sends them to that process, so nothing
  another test logs can take it away. It runs inside `capture_log/1`, which
  keeps the output off the console.
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

  # The handler runs in the logging process, so every event is in the
  # mailbox once `fun` has returned
  defp collect(ref, acc) do
    receive do
      {^ref, chardata} -> collect(ref, [acc, chardata])
    after
      0 -> acc
    end
  end

  @doc false
  def log(%{meta: %{pid: pid}} = event, %{config: %{pid: pid, ref: ref}}) do
    {formatter, config} = Logger.default_formatter(colors: [enabled: false])
    send(pid, {ref, formatter.format(event, config)})
  end

  def log(_event, _config), do: :ok
end
