defmodule Brando.Sites.FourOhFour.Flusher do
  @moduledoc """
  Writes the node's buffered 404 counts to the database every
  `Brando.Sites.FourOhFour.flush_interval/0`, and once more when the node
  shuts down, so a deploy does not lose the last interval's hits. The buffer
  is per node, so every node runs one.
  """
  use GenServer

  alias Brando.Sites.FourOhFour

  @doc "The flusher as a child spec, or none when `flush_interval` is `false`."
  @spec children() :: [Supervisor.child_spec()]
  def children do
    case FourOhFour.flush_interval() do
      interval when is_integer(interval) and interval > 0 -> [{__MODULE__, interval}]
      _ -> []
    end
  end

  def start_link(interval), do: GenServer.start_link(__MODULE__, interval, name: __MODULE__)

  @impl true
  def init(interval) do
    Process.flag(:trap_exit, true)
    schedule(interval)
    {:ok, interval}
  end

  @impl true
  def handle_info(:flush, interval) do
    FourOhFour.flush()
    schedule(interval)
    {:noreply, interval}
  end

  def handle_info(_message, interval), do: {:noreply, interval}

  @impl true
  def terminate(_reason, _interval), do: FourOhFour.flush()

  defp schedule(interval), do: Process.send_after(self(), :flush, interval)
end
