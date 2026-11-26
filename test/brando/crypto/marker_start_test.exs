defmodule Brando.Crypto.MarkerStartTest do
  # The check at start as a serving node runs it: outside the SQL sandbox,
  # each process on a connection of its own, so two nodes meet at the row
  # lock and a hung check waits on Postgres. What a test commits is removed
  # after it.
  use ExUnit.Case, async: false

  import Brando.Test.Support
  import Ecto.Query, only: [from: 2]

  alias Brando.Activity.Event
  alias Brando.Crypto.Marker
  alias Brando.Test.ForeignSecret
  alias Brando.Webhooks.Webhook
  alias BrandoIntegration.Repo
  alias Ecto.Adapters.SQL.Sandbox

  @context "brando.crypto_marker"

  setup do
    Sandbox.mode(Repo, :auto)

    on_exit(fn ->
      Repo.delete_all(Marker)
      Repo.delete_all(from(e in Event, where: e.schema == ^to_string(Webhook)))
      Repo.delete_all(Webhook)
      Sandbox.mode(Repo, :manual)
    end)
  end

  defp moved_marker!,
    do: Repo.insert!(%Marker{id: 1, value: Brando.Crypto.encrypt("brando", @context), host: "prod.example.com"})

  # A transaction elsewhere that holds `query`'s rows until it is told to let go
  defp hold(query) do
    parent = self()

    holder =
      Task.async(fn ->
        Repo.transaction(fn ->
          Repo.all(query)
          send(parent, :held)

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive :held, 5_000
    holder
  end

  defp release(holder) do
    send(holder.pid, :release)
    Task.await(holder)
  end

  # Until `count` backends of this database wait for a lock
  defp await_lock_waiters(count, tries \\ 100) do
    %{rows: [[waiting]]} =
      Repo.query!(
        "SELECT count(*)::int FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock'"
      )

    cond do
      waiting >= count ->
        :ok

      tries == 0 ->
        flunk("#{waiting} of #{count} sessions came to wait on a lock")

      true ->
        Process.sleep(50)
        await_lock_waiters(count, tries - 1)
    end
  end

  defp capture(fun) do
    previous = Logger.level()
    Logger.configure(level: :warning)

    try do
      ExUnit.CaptureLog.with_log([level: :warning], fun)
    after
      Logger.configure(level: previous)
    end
  end

  describe "children/0" do
    test "a node that serves the endpoint, outside the SQL sandbox, gets the check" do
      assert Marker.children() == []

      put_test_env(
        BrandoIntegrationWeb.Endpoint,
        Keyword.put(Brando.config(BrandoIntegrationWeb.Endpoint), :server, true)
      )

      # Still the sandbox
      assert Marker.children() == []

      put_test_env(
        BrandoIntegration.Repo,
        Keyword.put(Brando.config(BrandoIntegration.Repo), :pool, DBConnection.ConnectionPool)
      )

      assert [%{id: Marker, start: {Marker, :start_link, []}}] = Marker.children()
    end
  end

  describe "start_link/0" do
    test "a check that raises lets the node start" do
      # No marker: the check writes one, and an unusable secret raises
      put_test_env(Brando.Crypto, secret: "too short")

      {result, log} = capture(fn -> Marker.start_link() end)

      assert result == :ignore
      assert log =~ "Could not check the encryption marker at start"
    end

    @tag timeout: 30_000
    test "a check that hangs is given up after the timeout, and the node starts" do
      moved_marker!()
      holder = hold(from(m in Marker, lock: "FOR UPDATE"))

      try do
        {{microseconds, result}, log} = capture(fn -> :timer.tc(&Marker.start_link/0) end)

        assert result == :ignore
        assert log =~ "did not finish in time"
        assert microseconds in 5_000_000..8_000_000
      after
        release(holder)
      end

      # Given up before it changed anything
      assert %Marker{host: "prod.example.com", moved_at: nil} = Repo.one(Marker)
    end
  end

  test "two nodes starting at once on their own connections pause once" do
    moved_marker!()
    hook = ForeignSecret.webhook!(nil, true)

    # Both nodes have read the marker before either writes: the first waits
    # here for the webhook, the second for the marker's lock
    holder = hold(from(w in Webhook, where: w.id == ^hook.id, lock: "FOR UPDATE"))
    nodes = for _ <- 1..2, do: Task.async(fn -> capture(&Marker.check_at_start/0) end)
    await_lock_waiters(2)
    release(holder)

    assert [{:ok, _}, {:ok, _}] = Task.await_many(nodes, 10_000)
    assert %Marker{paused: [%{"count" => 1}]} = Repo.one(Marker)
    assert Repo.aggregate(from(e in Event, where: e.schema == ^to_string(Webhook)), :count) == 1
  end
end
