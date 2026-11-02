defmodule Brando.MarkdownSources.RateLimiter do
  @moduledoc false
  # Per-minute budgets for the GitHub Markdown webhook, on this node. Every
  # request counts against its client (120). Only a delivery whose signature
  # verified counts against the deliveries' budget (1,200), so unsigned requests
  # cannot use that up. A loose cap for all requests (12,000) applies to those
  # for a key no connection has: they cost no signature work, and past the cap
  # they are refused. Requests for a known key go on past it, or anyone could
  # refuse signed deliveries by filling it, since a key in a webhook URL is no
  # secret; `Brando.MarkdownSources.SignatureCheck` bounds the work those cause.
  use GenServer

  @per_client 120
  @all_requests 12_000
  @verified 1200

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  def init(_), do: {:ok, fresh(nil)}

  @doc """
  Counts a request from `address`; true while it is within its budget.
  `known_key?` says the request names a connection, which the cap does not refuse.
  """
  def allow_client?(address, known_key?),
    do: GenServer.call(__MODULE__, {:client, client(address), known_key?})

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
  # so no one client can fill it. Past the cap a request for an unknown key adds
  # nothing, and one for a known key still counts against its client. The map
  # starts empty every minute, so it holds at most one entry per client the node
  # accepts a request from in a minute, at about 100 bytes each.
  defp count({:client, key, known_key?}, _from, state) do
    count = Map.get(state.clients, key, 0)
    counted = %{state | clients: Map.put(state.clients, key, count + 1)}

    cond do
      count >= @per_client ->
        {:reply, false, counted}

      state.requests < @all_requests ->
        {:reply, true, %{counted | requests: state.requests + 1}}

      not known_key? ->
        {:reply, false, state}

      true ->
        {:reply, true, counted}
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
