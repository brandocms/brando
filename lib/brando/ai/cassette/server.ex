defmodule Brando.AI.Cassette.Server do
  @moduledoc false
  # One cassette in use: its recorded interactions, which of them have been
  # played, what was recorded and what failed to match. Owned by the process
  # that started it (a test), and found from that process and every process
  # that has it among its `$callers`, through a public ETS table.
  #
  # The server is not linked to the test: a tag's cassette is checked in an
  # `on_exit` callback, after the test process has exited.

  use GenServer

  alias Brando.AI.Cassette.Matcher

  @table Brando.AI.Cassette.Registry

  ## Registry

  @doc "The cassette server for the calling process, if one of it or its callers owns one."
  def lookup do
    case :ets.whereis(@table) do
      :undefined -> nil
      _ -> Enum.find_value([self() | Process.get(:"$callers", [])], &find/1)
    end
  end

  defp find(pid) do
    case :ets.lookup(@table, pid) do
      [{^pid, server}] -> server
      [] -> nil
    end
  end

  defp register(owner, server) do
    ensure_table()

    if :ets.insert_new(@table, {owner, server}),
      do: :ok,
      else: {:error, :already_active}
  end

  defp unregister(owner) do
    if :ets.whereis(@table) != :undefined, do: :ets.delete(@table, owner)
    :ok
  end

  # The table belongs to a small process of its own, started on first use, so
  # it outlives the test that created it.
  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      case GenServer.start(__MODULE__.Holder, nil, name: __MODULE__.Holder) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end

      GenServer.call(__MODULE__.Holder, :ready)
    end
  end

  defmodule Holder do
    @moduledoc false
    use GenServer

    @impl true
    def init(nil) do
      :ets.new(Brando.AI.Cassette.Registry, [:named_table, :public, :set, read_concurrency: true])
      {:ok, nil}
    end

    @impl true
    def handle_call(:ready, _from, state), do: {:reply, :ok, state}
  end

  ## Lifecycle

  @doc "Start a cassette for `owner` with the cassette state `state`."
  def start(owner, state) do
    {:ok, server} = GenServer.start(__MODULE__, state)

    case register(owner, server) do
      :ok ->
        {:ok, server}

      {:error, _} = error ->
        GenServer.stop(server)
        error
    end
  end

  @doc "Stop the cassette `owner` owns and return its final state."
  def stop(owner, server) do
    unregister(owner)
    state = GenServer.call(server, :state)
    GenServer.stop(server)
    state
  end

  def state(server), do: GenServer.call(server, :state)

  @doc "The recorded reply for `request`, or the mismatch."
  def play(server, request), do: GenServer.call(server, {:play, request})

  def bind(server, bindings), do: GenServer.call(server, {:bind, bindings})

  def record(server, request, reply), do: GenServer.call(server, {:record, request, reply})

  @doc "Note a failure that the test should report at the end, such as a mismatch in another process."
  def fail(server, error), do: GenServer.cast(server, {:fail, error})

  ## Server

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:state, _from, state), do: {:reply, state, state}

  def handle_call({:play, request}, _from, %{stub: stub} = state) when is_function(stub, 1) do
    {:reply, {:ok, stub.(request)}, %{state | played: state.played ++ [request]}}
  end

  def handle_call({:play, request}, _from, state) do
    candidates = state.interactions |> Enum.with_index() |> Enum.reject(fn {_, i} -> i in state.used end)

    case Enum.find(candidates, fn {interaction, _} -> Matcher.match?(interaction["request"], request, state.match_on) end) do
      {interaction, index} ->
        {:reply, {:ok, interaction["response"]}, %{state | used: [index | state.used], played: state.played ++ [request]}}

      nil ->
        error = Matcher.mismatch(state, request)
        {:reply, {:error, error}, %{state | failures: state.failures ++ [error]}}
    end
  end

  def handle_call({:bind, bindings}, _from, state),
    do: {:reply, :ok, %{state | bindings: Map.merge(state.bindings, bindings)}}

  def handle_call({:record, request, reply}, _from, state) do
    interaction = %{"request" => request, "response" => reply}
    {:reply, :ok, %{state | recorded: state.recorded ++ [interaction], played: state.played ++ [request]}}
  end

  @impl true
  def handle_cast({:fail, error}, state), do: {:noreply, %{state | failures: state.failures ++ [error]}}
end
