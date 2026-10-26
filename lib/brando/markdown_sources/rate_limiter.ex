defmodule Brando.MarkdownSources.RateLimiter do
  @moduledoc false
  # Per-minute budgets for the GitHub Markdown webhook, on this node. Every
  # request counts against its client (120); only a delivery whose signature
  # verified counts against the node-wide budget (1,200), so unsigned or
  # forged requests cannot use it up and hold back GitHub's deliveries.
  use GenServer

  @per_client 120
  @verified 1200

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  def init(_), do: {:ok, fresh(nil)}

  @doc "Counts a request from `address`; true while it is within its budget."
  def allow_client?(address), do: GenServer.call(__MODULE__, {:client, :erlang.phash2(address, 2048)})

  @doc "Counts a verified delivery; true while the node's budget allows it."
  def allow_delivery?, do: GenServer.call(__MODULE__, :delivery)

  @doc false
  def reset, do: GenServer.call(__MODULE__, :reset)

  def handle_call(:reset, _, _state), do: {:reply, :ok, fresh(nil)}

  def handle_call(request, from, state) do
    window = div(System.monotonic_time(:second), 60)
    state = if state.window == window, do: state, else: fresh(window)
    count(request, from, state)
  end

  defp count({:client, key}, _from, state) do
    count = Map.get(state.clients, key, 0)
    {:reply, count < @per_client, %{state | clients: Map.put(state.clients, key, count + 1)}}
  end

  defp count(:delivery, _from, state) do
    {:reply, state.deliveries < @verified, %{state | deliveries: state.deliveries + 1}}
  end

  defp fresh(window), do: %{window: window, deliveries: 0, clients: %{}}
end
