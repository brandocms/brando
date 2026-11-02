defmodule Brando.CacheSync do
  @moduledoc """
  Keeps the per-node caches in step across a cluster: the `:persistent_term`
  caches of sites, environments, site assets and the shared library, and the
  Cachex site caches (identity, SEO, globals, palettes, menus) and query
  cache.

  These caches belong to one node. A write refreshes the writing node's
  cache itself and calls `broadcast/2`, which tells every node over PubSub once
  the transaction around the caller has committed, so a node that reads the
  database on hearing it reads the write. Each node runs one of these
  processes under `Brando.Supervisor`: it skips its own node's messages, whose
  cache is already fresh, and refreshes for the rest. A node knows its own by
  an id drawn when it boots, not by its node name: servers outside an Erlang
  cluster are all `nonode@nohost`, and a PubSub adapter such as
  `phoenix_pubsub_redis` still connects them.

  A burst of writes refreshes once: messages heard within 100 ms of the first
  are gathered, and each distinct refresh runs once when that time is up.
  Refreshes sent for every save (the query cache's evictions) go through
  `broadcast_gathered/2`, which gathers them on the sending node for 100 ms
  as well and sends them together, at most 100 to a message. A
  refresh that raises (the database briefly unreachable, say) is tried again
  twice, five seconds apart, then logged.

  A cache takes part by being listed here and implementing
  `refresh_node_cache/1`, which refreshes this node's copy for a refresh
  another node broadcast: `Brando.Tenant.Cache`, `Brando.Assets.SiteAssets`,
  the shared-library allowlists of `Brando.Content.SharedLibrary`, the site
  caches through `Brando.Cache` and `Brando.Cache.Query`.

  A node cut off from the others when a write is broadcast does not hear it,
  and keeps its copy until the next write or a restart.
  """
  use GenServer

  require Logger

  @topic "brando:cache_sync"
  @caches [
    Brando.Tenant.Cache,
    Brando.Assets.SiteAssets,
    Brando.Content.SharedLibrary.Cache,
    Brando.Cache,
    Brando.Cache.Query
  ]
  @origin_key {__MODULE__, :origin}
  @debounce 100
  @batch_size 100
  @retry_after :timer.seconds(5)
  @attempts 3

  @doc "The PubSub topic refreshes are broadcast on."
  @spec topic() :: String.t()
  def topic, do: @topic

  @doc """
  Tells the other nodes to run `cache.refresh_node_cache(refresh)`, once the
  transaction around the caller has committed (at once outside one). Without
  a running PubSub (a mix task) there are no other nodes to tell.
  """
  @spec broadcast(module(), term()) :: :ok
  def broadcast(cache, refresh) when cache in @caches do
    Brando.Repo.after_commit({__MODULE__, cache, refresh}, fn -> publish({cache, refresh}) end)
  end

  @doc """
  Like `broadcast/2`, for refreshes that come with every save: once the
  transaction has committed, this node gathers them for 100 ms, a refresh
  sent several times once, and sends them together. Without a running
  `Brando.CacheSync` (a mix task) there are no other nodes to tell.
  """
  @spec broadcast_gathered(module(), term()) :: :ok
  def broadcast_gathered(cache, refresh) when cache in @caches do
    Brando.Repo.after_commit({__MODULE__, cache, refresh}, fn -> GenServer.cast(__MODULE__, {:send, {cache, refresh}}) end)
  end

  # Rescued here, as it may run after the commit, in the repo's held work
  defp publish(refresh) do
    Phoenix.PubSub.broadcast(Brando.pubsub(), @topic, {:brando_cache_sync, origin(), refresh})
  rescue
    # No PubSub registry under that name
    ArgumentError -> :ok
  end

  @doc false
  # This node's id, drawn once per boot. Without a running `Brando.CacheSync`
  # there is none, and no process here to skip the message.
  @spec origin() :: binary() | nil
  def origin, do: :persistent_term.get(@origin_key, nil)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Sends the refreshes gathered and runs the ones heard so far, at once. For tests."
  @spec sync() :: :ok
  def sync, do: GenServer.call(__MODULE__, :sync)

  @impl true
  def init(nil) do
    # Kept when this process restarts: a boot's messages stay its own
    unless origin(), do: :persistent_term.put(@origin_key, Base.url_encode64(:crypto.strong_rand_bytes(12)))
    :ok = Phoenix.PubSub.subscribe(Brando.pubsub(), @topic)
    {:ok, %{pending: %{}, timer: nil, outgoing: MapSet.new(), send_timer: nil}}
  end

  @impl true
  def handle_call(:sync, _from, state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    if state.send_timer, do: Process.cancel_timer(state.send_timer)
    {:reply, :ok, state |> send_gathered() |> Map.put(:timer, nil) |> run()}
  end

  @impl true
  def handle_cast({:send, refresh}, state) do
    timer = state.send_timer || Process.send_after(self(), :send, @debounce)
    {:noreply, %{state | outgoing: MapSet.put(state.outgoing, refresh), send_timer: timer}}
  end

  @impl true
  def handle_info({:brando_cache_sync, origin, {:batch, refreshes}}, state) when is_list(refreshes) do
    if origin == origin(),
      do: {:noreply, state},
      else: {:noreply, Enum.reduce(refreshes, state, &pend_heard/2)}
  end

  def handle_info({:brando_cache_sync, origin, {cache, _refresh} = refresh}, state) when cache in @caches do
    if origin == origin(), do: {:noreply, state}, else: {:noreply, pend(state, refresh, 1)}
  end

  def handle_info(:send, state), do: {:noreply, send_gathered(state)}

  def handle_info({:retry, refresh, attempt}, state), do: {:noreply, pend(state, refresh, attempt)}

  def handle_info(:refresh, state), do: {:noreply, run(%{state | timer: nil})}

  def handle_info(_message, state), do: {:noreply, state}

  defp pend_heard({cache, _refresh} = refresh, state) when cache in @caches, do: pend(state, refresh, 1)
  defp pend_heard(_unknown, state), do: state

  defp send_gathered(state) do
    state.outgoing
    |> Enum.chunk_every(@batch_size)
    |> Enum.each(&publish({:batch, &1}))

    %{state | outgoing: MapSet.new(), send_timer: nil}
  end

  # A refresh already waiting keeps its fewer attempts: the newer write
  # deserves as many as the first.
  defp pend(state, refresh, attempt) do
    pending = Map.update(state.pending, refresh, attempt, &min(&1, attempt))
    timer = state.timer || Process.send_after(self(), :refresh, @debounce)
    %{state | pending: pending, timer: timer}
  end

  defp run(state) do
    Enum.each(state.pending, fn {refresh, attempt} -> refresh(refresh, attempt) end)
    %{state | pending: %{}}
  end

  defp refresh({cache, refresh} = message, attempt) do
    cache.refresh_node_cache(refresh)
  rescue
    error -> failed(message, attempt, Exception.format(:error, error, __STACKTRACE__))
  catch
    kind, reason -> failed(message, attempt, Exception.format(kind, reason, __STACKTRACE__))
  end

  defp failed(message, attempt, _error) when attempt < @attempts,
    do: Process.send_after(self(), {:retry, message, attempt + 1}, @retry_after)

  defp failed(message, _attempt, error),
    do: Logger.error("[Brando.CacheSync] Could not refresh #{inspect(message)} from another node: " <> error)
end
