defmodule Brando.MarkdownSources.Slots do
  @moduledoc false
  # A fixed number of slots the GitHub Markdown webhook's requests take turns
  # in (`Brando.MarkdownSources.ReadSlots`, `Brando.MarkdownSources.SignatureCheck`).
  # The work runs in the caller's process: only small tags pass through here,
  # never a body. A request waits for a slot, first come first served within
  # its line, with the `:first` line served before `:others`, and is refused
  # only when its deadline passes. A slot whose holder dies is given back.
  use GenServer

  def child_spec(opts) do
    %{id: Keyword.fetch!(opts, :name), start: {__MODULE__, :start_link, [opts]}}
  end

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, Keyword.fetch!(opts, :slots), name: Keyword.fetch!(opts, :name))

  def init(slots),
    do:
      {:ok,
       %{free: slots, holders: %{}, waiting: %{}, queues: %{first: :queue.new(), others: :queue.new()}, monitors: %{}}}

  @doc """
  The result of `fun`, run holding a slot of `name`; `{:error, :busy}` when no
  slot is free before `deadline` (monotonic milliseconds, or `:infinity`).
  `line` is `:first` or `:others`.
  """
  def run(name, deadline, fun, line \\ :others) when is_function(fun, 0) and line in [:first, :others] do
    tag = make_ref()

    try do
      GenServer.call(name, {:checkout, tag, line}, timeout(deadline))
    catch
      :exit, {:timeout, _} ->
        # A slot given after the timeout goes back; a late reply is dropped.
        # A cancel the server is too busy to answer in time is still queued
        # and gives the slot back when handled, so the request is refused as
        # busy rather than exiting.
        try do
          GenServer.call(name, {:cancel, tag})
        catch
          :exit, _ -> :ok
        end

        {:error, :busy}
    else
      :ok ->
        try do
          fun.()
        after
          GenServer.cast(name, {:checkin, tag})
        end
    end
  end

  defp timeout(:infinity), do: :infinity
  defp timeout(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)

  def handle_call({:checkout, tag, line}, {pid, _} = from, state) do
    monitor = Process.monitor(pid)
    state = put_in(state.monitors[monitor], tag)

    if state.free > 0 do
      {:reply, :ok, %{state | free: state.free - 1, holders: Map.put(state.holders, tag, monitor)}}
    else
      state = update_in(state.queues[line], &:queue.in(tag, &1))
      {:noreply, %{state | waiting: Map.put(state.waiting, tag, {from, monitor})}}
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
  # place in its queue is skipped when reached), or after it already left.
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
    case next(state.queues) do
      :empty ->
        %{state | free: state.free + 1}

      {tag, queues} ->
        case Map.pop(state.waiting, tag) do
          {nil, _} ->
            hand_over(%{state | queues: queues})

          {{from, monitor}, waiting} ->
            GenServer.reply(from, :ok)
            %{state | queues: queues, waiting: waiting, holders: Map.put(state.holders, tag, monitor)}
        end
    end
  end

  # `others` is dequeued only when `first` is empty: a dequeue may reverse a
  # queue's rear list, work a hand-over to `first` must not repeat over the
  # backlog from other addresses.
  defp next(%{first: first, others: others} = queues) do
    case :queue.out(first) do
      {{:value, tag}, first} ->
        {tag, %{queues | first: first}}

      {:empty, _} ->
        case :queue.out(others) do
          {{:value, tag}, others} -> {tag, %{queues | others: others}}
          {:empty, _} -> :empty
        end
    end
  end
end
