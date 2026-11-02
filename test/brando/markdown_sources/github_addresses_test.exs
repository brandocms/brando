defmodule Brando.MarkdownSources.GitHubAddressesTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  alias Brando.MarkdownSources.{GitHubAddresses, ReadSlots}

  @name :github_addresses_test

  # Answers from a list the test sets, and tells the test each URL it was asked for
  defmodule Meta do
    def meta(url) do
      send(Application.get_env(:brando, :github_meta_test_pid), {:meta, url})

      Agent.get_and_update(Brando.MarkdownSources.GitHubAddressesTest.Answers, fn
        [answer | rest] -> {answer, rest}
        [] -> {{:error, :no_answer}, []}
      end)
    end
  end

  setup do
    old = Application.get_env(:brando, :markdown_sources)
    connections = %{"docs" => %{secret: String.duplicate("s", 40), repository: "acme/docs", repository_id: 42}}
    Application.put_env(:brando, :markdown_sources, connections: connections)
    Application.put_env(:brando, :github_meta_test_pid, self())

    on_exit(fn ->
      if old,
        do: Application.put_env(:brando, :markdown_sources, old),
        else: Application.delete_env(:brando, :markdown_sources)

      Application.delete_env(:brando, :github_meta_test_pid)
      :persistent_term.erase({GitHubAddresses, @name})
    end)

    :ok
  end

  defp answers(list),
    do: start_supervised!(%{id: :answers, start: {Agent, :start_link, [fn -> list end, [name: __MODULE__.Answers]]}})

  defp start do
    pid = start_supervised!({GitHubAddresses, name: @name, client: Meta})
    :sys.get_state(pid)
    pid
  end

  defp refresh(pid) do
    send(pid, :fetch)
    :sys.get_state(pid)
  end

  defp config(extra),
    do: Application.put_env(:brando, :markdown_sources, Application.get_env(:brando, :markdown_sources) ++ extra)

  test "fetches GitHub's hooks ranges when it starts" do
    answers([{:ok, %{"hooks" => ["192.30.252.0/22", "2606:50c0::/32"], "web" => ["0.0.0.0/0"]}}])
    start()

    assert_received {:meta, "https://api.github.com/meta"}
    assert GitHubAddresses.member?({192, 30, 255, 1}, @name)
    assert GitHubAddresses.member?({0x2606, 0x50C0, 9, 0, 0, 0, 0, 1}, @name)
    refute GitHubAddresses.member?({192, 30, 251, 1}, @name)
    refute GitHubAddresses.member?(nil, @name)
  end

  test "asks the configured URL, for GitHub Enterprise" do
    config(github_meta_url: "https://github.example.com/api/v3/meta")
    answers([{:ok, %{"hooks" => ["10.0.0.0/24"]}}])
    start()

    assert_received {:meta, "https://github.example.com/api/v3/meta"}
    assert GitHubAddresses.member?({10, 0, 0, 7}, @name)
  end

  test "a failed or invalid fetch keeps the last good list" do
    answers([
      {:ok, %{"hooks" => ["192.30.252.0/22"]}},
      {:error, :github_unavailable},
      {:ok, %{"hooks" => ["0.0.0.0/0"]}},
      {:ok, %{"hooks" => ["192.30.252.0/22", "not a range"]}},
      {:ok, %{"hooks" => []}},
      {:ok, %{"web" => ["185.199.108.0/22"]}}
    ])

    pid = start()
    before = GitHubAddresses.ranges(@name)

    capture_log(fn -> for _ <- 1..5, do: refresh(pid) end)
    assert GitHubAddresses.ranges(@name) == before
    assert GitHubAddresses.member?({192, 30, 252, 1}, @name)
    refute GitHubAddresses.member?({8, 8, 8, 8}, @name)
  end

  test "with no list fetched, no address is GitHub's" do
    answers([{:error, :github_unavailable}])

    capture_log(fn -> start() end)
    assert GitHubAddresses.ranges(@name) == []
    refute GitHubAddresses.member?({192, 30, 252, 1}, @name)
  end

  test "a fixed list in config is used and nothing is fetched" do
    config(github_hook_ranges: ["192.30.252.0/22", "nonsense"])

    assert GitHubAddresses.start_link(name: @name, client: Meta) == :ignore
    assert GitHubAddresses.member?({192, 30, 252, 1}, @name)
    refute_received {:meta, _}
  end

  test "nothing is fetched without connections or with no URL" do
    Application.put_env(:brando, :markdown_sources, connections: %{})
    assert GitHubAddresses.start_link(name: @name, client: Meta) == :ignore

    Application.put_env(:brando, :markdown_sources,
      connections: %{"docs" => %{}},
      github_meta_url: nil
    )

    assert GitHubAddresses.start_link(name: @name, client: Meta) == :ignore
    refute_received {:meta, _}
  end

  describe "read slots" do
    defp hold(parent) do
      spawn(fn ->
        ReadSlots.run(System.monotonic_time(:millisecond) + 5_000, fn ->
          send(parent, {:holding, self()})
          receive do: (:release -> :ok)
        end)
      end)
    end

    defp wait_until(check) do
      if check.(),
        do: :ok,
        else:
          (
            Process.sleep(5)
            wait_until(check)
          )
    end

    defp fill do
      holders = for _ <- 1..16, do: hold(self())
      for _ <- 1..16, do: assert_receive({:holding, _})
      on_exit(fn -> Enum.each(holders, &Process.exit(&1, :kill)) end)
      holders
    end

    test "a request waits for a slot and is refused only past its deadline" do
      fill()
      deadline = System.monotonic_time(:millisecond) + 100
      assert ReadSlots.run(deadline, fn -> :ran end) == {:error, :busy}
      assert System.monotonic_time(:millisecond) >= deadline
    end

    test "a slot given back goes to the first in line" do
      [first | _] = fill()
      parent = self()

      for n <- 1..2 do
        waiter =
          spawn(fn ->
            ReadSlots.run(System.monotonic_time(:millisecond) + 5_000, fn ->
              send(parent, {:running, n})
              receive do: (:release -> :ok)
            end)
          end)

        on_exit(fn -> Process.exit(waiter, :kill) end)
        # Queued in this order
        wait_until(fn -> map_size(:sys.get_state(ReadSlots).waiting) == n end)
      end

      send(first, :release)
      assert_receive {:running, 1}
      refute_receive {:running, 2}, 50
    end

    test "a request that gave up waiting leaves no slot taken" do
      holders = fill()
      assert ReadSlots.run(System.monotonic_time(:millisecond) + 50, fn -> :ran end) == {:error, :busy}

      for holder <- holders do
        ref = Process.monitor(holder)
        send(holder, :release)
        assert_receive {:DOWN, ^ref, _, _, _}
      end

      state = :sys.get_state(ReadSlots)
      assert state.free == 16
      assert state.holders == %{} and state.waiting == %{} and state.monitors == %{}
    end

    test "a holder that dies gives its slot back" do
      [first | _] = fill()
      Process.exit(first, :kill)
      assert ReadSlots.run(System.monotonic_time(:millisecond) + 1_000, fn -> :ran end) == :ran
    end
  end
end
