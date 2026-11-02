defmodule Brando.MarkdownSources.SlotsTest do
  use ExUnit.Case, async: true
  alias Brando.MarkdownSources.Slots

  setup context do
    name = Module.concat(__MODULE__, "Slots#{System.unique_integer([:positive])}")
    pid = start_supervised!(Slots.child_spec(name: name, slots: context[:slots] || 1))
    %{name: name, pid: pid}
  end

  defp wait_until(check, tries \\ 400) do
    cond do
      check.() ->
        :ok

      tries == 0 ->
        flunk("condition not met in time")

      true ->
        Process.sleep(5)
        wait_until(check, tries - 1)
    end
  end

  defp hold(name, line) do
    parent = self()

    pid =
      spawn(fn ->
        Slots.run(
          name,
          :infinity,
          fn ->
            send(parent, {:holding, self()})
            receive do: (:release -> :ok)
          end,
          line
        )
      end)

    on_exit(fn -> Process.exit(pid, :kill) end)
    pid
  end

  test "handing a slot to the first line does no work over the others' backlog", %{name: name, pid: pid} do
    holder = hold(name, :others)
    assert_receive {:holding, ^holder}

    # A backlog from other addresses as `:queue.in/2` builds it: one tag in
    # front, the rest in the rear list, which a dequeue has to reverse
    backlog = Enum.reduce(1..200_000, :queue.new(), fn _, queue -> :queue.in(make_ref(), queue) end)
    :sys.replace_state(pid, &put_in(&1.queues.others, backlog))

    firsts = for _ <- 1..5, do: hold(name, :first)
    wait_until(fn -> map_size(:sys.get_state(pid).waiting) == 5 end)

    {:reductions, before} = Process.info(pid, :reductions)
    send(holder, :release)

    # Measured while the last one holds: its release goes on to the backlog
    {waiting_firsts, [last]} = Enum.split(firsts, -1)

    for first <- waiting_firsts do
      assert_receive {:holding, ^first}
      send(first, :release)
    end

    assert_receive {:holding, ^last}
    {:reductions, after_handovers} = Process.info(pid, :reductions)

    assert after_handovers - before < 50_000
  end

  @tag timeout: 20_000
  test "a cancel the server is too busy to answer still refuses the request as busy", %{name: name, pid: pid} do
    :sys.suspend(pid)

    assert Slots.run(name, System.monotonic_time(:millisecond) + 50, fn -> :ran end) == {:error, :busy}

    # The grant and the cancel, both queued, are handled once the server catches up
    :sys.resume(pid)
    assert %{free: 1, holders: holders, waiting: waiting, monitors: monitors} = :sys.get_state(pid)
    assert holders == %{} and waiting == %{} and monitors == %{}
  end
end
