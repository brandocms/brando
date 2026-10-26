defmodule Brando.MarkdownSources.RateLimiter do
  @moduledoc false
  # Per-minute budgets for the GitHub Markdown webhook, on this node. Every
  # request counts against its client (120) and a loose cap for all requests
  # (12,000), which bounds the work unsigned ones cause; only a delivery
  # whose signature verified counts against the deliveries' budget (1,200),
  # so unsigned or forged requests cannot use it up and hold back GitHub's.
  use GenServer

  @per_client 120
  @all_requests 12_000
  @verified 1200

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  def init(_), do: {:ok, fresh(nil)}

  @doc "Counts a request from `address`; true while it is within its budget."
  def allow_client?(address), do: GenServer.call(__MODULE__, {:client, client(address)})

  @doc "Counts a verified delivery; true while the node's budget allows it."
  def allow_delivery?, do: GenServer.call(__MODULE__, :delivery)

  @doc false
  # For tests: forgets every count. `freeze: true` keeps one window until the
  # next reset, so a test's counts never roll over at a minute's end.
  def reset(opts \\ []), do: GenServer.call(__MODULE__, {:reset, Keyword.get(opts, :freeze, false)})

  def handle_call({:reset, freeze?}, _, _state), do: {:reply, :ok, %{fresh(nil) | frozen: freeze?}}

  def handle_call(request, from, state) do
    window = div(System.monotonic_time(:second), 60)
    state = if state.window == window or state.frozen, do: state, else: fresh(window)
    count(request, from, state)
  end

  # A client over its own budget is refused without touching the shared cap,
  # so no one client can fill it. Once it is full, no new client is added.
  defp count({:client, key}, _from, state) do
    count = Map.get(state.clients, key, 0)

    cond do
      count >= @per_client ->
        {:reply, false, %{state | clients: Map.put(state.clients, key, count + 1)}}

      state.requests >= @all_requests ->
        {:reply, false, state}

      true ->
        {:reply, true, %{state | requests: state.requests + 1, clients: Map.put(state.clients, key, count + 1)}}
    end
  end

  defp count(:delivery, _from, state) do
    {:reply, state.deliveries < @verified, %{state | deliveries: state.deliveries + 1}}
  end

  # Each client counts on its own, not in a shared hash bucket another could
  # fill; an IPv6 client by its /64. The map starts empty every minute.
  defp client(address), do: Brando.ClientIP.rate_key(address)

  defp fresh(window), do: %{window: window, requests: 0, deliveries: 0, clients: %{}, frozen: false}
end
