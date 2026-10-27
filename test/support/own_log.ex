defmodule Brando.Test.OwnLog do
  @moduledoc """
  What the calling process logs while `fun` runs, for tests that assert on it.

  `ExUnit.CaptureLog` captures through one `:logger` handler shared by every
  test, and every capture open at the time gets every process's events: in an
  async test, `capture_log(...) == ""` fails for another test's log line. It
  also formats each event in a task it waits five seconds for; when that wait
  fails under load, `:logger` removes the handler, and every capture open at
  the time returns `""` (the run's output shows
  `{removed_failing_handler,'Elixir.ExUnit.CaptureServer'}`).

  `capture/1` gets the events of the calling process and of the tasks it
  starts, formatted in place by a handler of this module's own. It runs inside
  `capture_log/1`, which keeps the output off the console.

  The handler is added once, by `install/0` from `test_helper.exs`, and stays.
  Adding and removing one per capture raced every other capture in the run:
  `:logger` takes the handler list when it is asked to remove a handler and
  writes it back once the handler is told, dropping a handler added
  meanwhile (that capture returned `""`), and on OTP 27 `Logger.flush/0`, which
  every `capture_log/1` calls, raised `{:error, {:not_found, id}}` for a
  handler removed while it listed them.
  """

  @table __MODULE__

  @doc """
  Adds the handler and the table of open captures. Call it once, before any
  test runs; the table belongs to the calling process.
  """
  @spec install() :: :ok
  def install do
    @table = :ets.new(@table, [:bag, :public, :named_table, read_concurrency: true])
    :logger.add_handler(__MODULE__, __MODULE__, %{})
  end

  @spec capture((-> any())) :: String.t()
  def capture(fun) do
    entry = {self(), make_ref()}
    true = :ets.insert(@table, entry)

    try do
      ExUnit.CaptureLog.capture_log(fun)
    after
      :ets.delete_object(@table, entry)
    end

    entry |> elem(1) |> collect([]) |> IO.chardata_to_string()
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

  # Runs in the logging process, for every event in the run: sends the
  # captures open in that process, or in a caller of it (a task names those in
  # `$callers`), the formatted event. It must not raise, or `:logger` removes
  # it for the rest of the run.
  @doc false
  def log(%{meta: meta} = event, _config) do
    captures =
      for pid <- [Map.get(meta, :pid, self()) | Process.get(:"$callers", [])],
          capture <- :ets.lookup(@table, pid),
          do: capture

    if captures != [] do
      chardata = format(event)
      for {pid, ref} <- captures, do: send(pid, {ref, chardata})
    end

    :ok
  end

  defp format(event) do
    {formatter, config} = Logger.default_formatter(colors: [enabled: false])
    formatter.format(event, config)
  catch
    kind, reason -> "[#{inspect(__MODULE__)}] could not format #{inspect(event)}: #{Exception.format(kind, reason)}\n"
  end
end
