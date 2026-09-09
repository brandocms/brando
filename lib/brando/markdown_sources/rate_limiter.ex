defmodule Brando.MarkdownSources.RateLimiter do
  @moduledoc false
  use GenServer
  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  def init(_), do: {:ok, %{window: nil, count: 0, clients: %{}}}
  def allow?(address), do: GenServer.call(__MODULE__, {:allow, :erlang.phash2(address, 2048)})

  def handle_call({:allow, key}, _, state) do
    window = div(System.monotonic_time(:second), 60)
    state = if state.window == window, do: state, else: %{window: window, count: 0, clients: %{}}
    count = Map.get(state.clients, key, 0)
    allowed = count < 120 and state.count < 1200
    {:reply, allowed, %{state | count: state.count + 1, clients: Map.put(state.clients, key, count + 1)}}
  end
end
