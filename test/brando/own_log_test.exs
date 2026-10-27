defmodule Brando.Test.OwnLogTest do
  # Removes ExUnit's capture handler, which every capture in the run shares
  use ExUnit.Case, async: false

  require Logger

  alias Brando.Test.OwnLog

  test "keeps what the process logged when ExUnit's capture handler is removed meanwhile" do
    # As `:logger` does when the handler crashes, here on another test's event
    lose_handler = fn -> :logger.remove_handler(ExUnit.CaptureServer) end

    assert ExUnit.CaptureLog.capture_log(fn ->
             lose_handler.()
             Logger.error("logged after the handler went")
           end) == ""

    log =
      OwnLog.capture(fn ->
        lose_handler.()
        Logger.error("logged after the handler went")
      end)

    assert log =~ "[error] logged after the handler went"
  end

  test "keeps what the process and its tasks log, and leaves out other processes" do
    log =
      OwnLog.capture(fn ->
        Logger.error("from the test")
        Task.await(Task.async(fn -> Logger.error("from its task") end))
        {pid, ref} = spawn_monitor(fn -> Logger.error("from another process") end)
        assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      end)

    assert log =~ "from the test"
    assert log =~ "from its task"
    refute log =~ "from another process"
  end

  # As the async tests of a partition do. With a handler added and removed per
  # capture, about one in ten came back without its event, and on OTP 27 some
  # raised from `Logger.flush/0`.
  test "captures in many processes at once each keep their own events" do
    handlers = :logger.get_handler_ids()

    results =
      1..16
      |> Task.async_stream(
        fn i ->
          for j <- 1..50 do
            line = "capture #{i}.#{j}"
            log = OwnLog.capture(fn -> Logger.error(line) end)
            log =~ line and not (log =~ "capture #{i + 1}.")
          end
        end,
        max_concurrency: 16,
        timeout: :infinity
      )
      |> Enum.flat_map(fn {:ok, kept} -> kept end)

    assert Enum.all?(results)
    assert Enum.sort(:logger.get_handler_ids()) == Enum.sort(handlers)
  end
end
