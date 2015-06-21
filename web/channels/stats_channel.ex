defmodule Brando.StatsChannel do
  @moduledoc """
  Channel for system information.
  """
  @interval 5000

  use Phoenix.Channel

  @info_memory [
    :total,
    :processes,
    :atom,
    :binary,
    :code,
    :ets]

  def join("stats", _auth_msg, socket) do
    send self, :update
    {:ok, socket}
  end

  def handle_info(:update, socket) do
    mem_list =
      :erlang.memory(@info_memory)
      |> Keyword.values
    :erlang.send_after(@interval, self, :update)
    push socket, "update", %{total_memory: Enum.at(mem_list, 0),
                             atom_memory: Enum.at(mem_list, 2)}
    {:noreply, socket}
  end
end