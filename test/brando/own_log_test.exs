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

  test "leaves out what other processes log" do
    log =
      OwnLog.capture(fn ->
        Logger.error("from the test")
        Task.await(Task.async(fn -> Logger.error("from another process") end))
      end)

    assert log =~ "from the test"
    refute log =~ "from another process"
  end
end
