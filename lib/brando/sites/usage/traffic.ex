defmodule Brando.Sites.Usage.Traffic do
  @moduledoc """
  This node's request counters, per site and UTC day, and the process that
  writes them to `Brando.Sites.Usage` every `Brando.Sites.Usage.flush_interval/0`
  and once more when the node shuts down.

  A request costs one `:ets.update_counter/4` on a public table with write
  concurrency (`count/3`): no query, no message to this process, and nothing
  that grows with the number of sites. The row for a site and day is created
  by the first request that counts on it.

  A flush takes what each row holds by subtracting it, so requests counted
  while it writes stay for the next one, and adds back what it could not
  write. Timer and shutdown flushes run in this one process, so they never
  overlap. Only started with `tenancy_mode: :multi`.
  """
  use GenServer

  require Logger

  alias Brando.Sites.Usage

  @table __MODULE__

  @doc "The counter process as a child spec, or none outside `tenancy_mode: :multi`."
  @spec children() :: [Supervisor.child_spec()]
  def children, do: if(Usage.enabled?(), do: [{__MODULE__, Usage.flush_interval()}], else: [])

  def start_link(interval), do: GenServer.start_link(__MODULE__, interval, name: __MODULE__)

  @doc """
  Counts one request of `bytes` for a site on a day. Does nothing when the
  counters are not running.
  """
  @spec count(pos_integer(), Date.t(), non_neg_integer()) :: :ok
  def count(site_id, day, bytes) do
    key = {site_id, day}
    :ets.update_counter(@table, key, [{2, 1}, {3, bytes}], {key, 0, 0})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc "Writes the counters now; for tests and for a node about to stop."
  @spec flush() :: :ok
  def flush, do: GenServer.call(__MODULE__, :flush, :infinity)

  @impl true
  def init(interval) do
    Process.flag(:trap_exit, true)
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true, decentralized_counters: true])
    schedule(interval)
    {:ok, interval}
  end

  @impl true
  def handle_call(:flush, _from, interval), do: {:reply, write(), interval}

  @impl true
  def handle_info(:flush, interval) do
    write()
    schedule(interval)
    {:noreply, interval, :hibernate}
  end

  def handle_info(_message, interval), do: {:noreply, interval}

  @impl true
  def terminate(_reason, _interval), do: write()

  defp schedule(interval), do: Process.send_after(self(), :flush, interval)

  defp write do
    case take() do
      [] ->
        :ok

      taken ->
        try do
          Usage.add_traffic(for {{site_id, day}, requests, bytes} <- taken, do: {site_id, day, requests, bytes})
        rescue
          error ->
            put_back(taken)
            Logger.warning("[Brando.Sites.Usage] Request counts kept for the next flush: #{Exception.message(error)}")
        end

        :ok
    end
  end

  # What each row holds, subtracted from it; rows left at zero go, and a
  # request after that creates its row again
  defp take do
    taken =
      for {key, requests, bytes} <- :ets.tab2list(@table), requests > 0 or bytes > 0 do
        :ets.update_counter(@table, key, [{2, -requests}, {3, -bytes}])
        {key, requests, bytes}
      end

    :ets.select_delete(@table, [{{:_, 0, 0}, [], [true]}])
    taken
  end

  defp put_back(taken) do
    for {key, requests, bytes} <- taken,
        do: :ets.update_counter(@table, key, [{2, requests}, {3, bytes}], {key, 0, 0})
  end
end
