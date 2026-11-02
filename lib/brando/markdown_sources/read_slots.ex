defmodule Brando.MarkdownSources.ReadSlots do
  @moduledoc false
  # Bounds how many bodies from GitHub's addresses the GitHub Markdown webhook
  # holds at once: such a request reads and verifies its body holding one of 16
  # slots, so they take at most 16 MiB however many arrive together. Their budget
  # per minute is larger than other clients' (`Brando.MarkdownSources.RateLimiter`),
  # so it bounds their reads a minute, not those at once. A request waits for a
  # slot, first come first served, and is refused only when its deadline passes:
  # a refusal at once would let wrongly signed requests refuse correctly signed
  # ones. A slot whose holder dies is given back.
  use GenServer

  @slots 16

  def start_link(_), do: GenServer.start_link(__MODULE__, @slots, name: __MODULE__)

  def init(slots), do: {:ok, %{free: slots, holders: %{}, waiting: %{}, queue: :queue.new(), monitors: %{}}}

  @doc """
  The result of `fun`, run holding a slot; `{:error, :busy}` when no slot is free
  before `deadline` (monotonic milliseconds).
  """
  def run(deadline, fun) when is_function(fun, 0) do
    tag = make_ref()

    try do
      GenServer.call(__MODULE__, {:checkout, tag}, max(deadline - System.monotonic_time(:millisecond), 0))
    catch
      :exit, {:timeout, _} ->
        # A slot given after the timeout goes back; a late reply is dropped
        GenServer.call(__MODULE__, {:cancel, tag})
        {:error, :busy}
    else
      :ok ->
        try do
          fun.()
        after
          GenServer.cast(__MODULE__, {:checkin, tag})
        end
    end
  end

  def handle_call({:checkout, tag}, {pid, _} = from, state) do
    monitor = Process.monitor(pid)
    state = put_in(state.monitors[monitor], tag)

    if state.free > 0 do
      {:reply, :ok, %{state | free: state.free - 1, holders: Map.put(state.holders, tag, monitor)}}
    else
      {:noreply, %{state | waiting: Map.put(state.waiting, tag, {from, monitor}), queue: :queue.in(tag, state.queue)}}
    end
  end

  def handle_call({:cancel, tag}, _from, state), do: {:reply, :ok, leave(state, tag)}

  def handle_cast({:checkin, tag}, state), do: {:noreply, leave(state, tag)}

  def handle_info({:DOWN, monitor, :process, _, _}, state) do
    case Map.fetch(state.monitors, monitor) do
      {:ok, tag} -> {:noreply, leave(state, tag)}
      :error -> {:noreply, state}
    end
  end

  # A tag leaves holding a slot (which goes to the next in line), waiting (its
  # place in the queue is skipped when reached), or after it already left.
  defp leave(state, tag) do
    cond do
      Map.has_key?(state.holders, tag) ->
        {monitor, holders} = Map.pop(state.holders, tag)
        Process.demonitor(monitor, [:flush])
        hand_over(%{state | holders: holders, monitors: Map.delete(state.monitors, monitor)})

      Map.has_key?(state.waiting, tag) ->
        {{_from, monitor}, waiting} = Map.pop(state.waiting, tag)
        Process.demonitor(monitor, [:flush])
        %{state | waiting: waiting, monitors: Map.delete(state.monitors, monitor)}

      true ->
        state
    end
  end

  defp hand_over(state) do
    case :queue.out(state.queue) do
      {:empty, _} ->
        %{state | free: state.free + 1}

      {{:value, tag}, queue} ->
        case Map.pop(state.waiting, tag) do
          {nil, _} ->
            hand_over(%{state | queue: queue})

          {{from, monitor}, waiting} ->
            GenServer.reply(from, :ok)
            %{state | queue: queue, waiting: waiting, holders: Map.put(state.holders, tag, monitor)}
        end
    end
  end
end
