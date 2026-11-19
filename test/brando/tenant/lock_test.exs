defmodule Brando.Tenant.LockTest do
  use Brando.ConnCase, async: false

  alias Brando.Tenant.Lock

  describe "with_timeout/3" do
    test "runs the callback once and returns what it returns, whatever that is" do
      key = "brando:lock-test:#{System.unique_integer([:positive])}"

      assert {:ok, :busy} =
               Lock.with_timeout(key, 200, fn ->
                 send(self(), :ran)
                 :busy
               end)

      assert_received :ran
      refute_received :ran
    end

    test "gives up at the deadline while no connection can be checked out, and never runs the callback" do
      key = "brando:lock-test:#{System.unique_integer([:positive])}"
      test = self()

      # Holds the test's one shared sandbox connection, as a busy pool would
      # hold all of its own
      holder =
        spawn_link(fn ->
          Brando.Repo.repo().checkout(fn ->
            send(test, :holding)

            receive do
              :release -> :ok
            after
              2_000 -> :ok
            end
          end)

          send(test, :released)
        end)

      assert_receive :holding

      started = System.monotonic_time(:millisecond)
      assert :busy = Lock.with_timeout(key, 150, fn -> send(test, :ran) end)
      waited = System.monotonic_time(:millisecond) - started

      assert waited < 1_000
      refute_received :ran

      send(holder, :release)
      assert_receive :released
      assert {:ok, :ran} = Lock.with_timeout(key, 150, fn -> :ran end)
    end
  end
end
