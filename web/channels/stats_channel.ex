defmodule Brando.StatsChannel do
  @moduledoc """
  Channel for system information.
  """
  @interval 5000
  @info_memory [
    :total,
    :processes,
    :atom,
    :binary,
    :code,
    :ets]

  use Phoenix.Channel

  def join("stats", _auth_msg, socket) do
    send self, :update
    {:ok, socket}
  end

  def handle_info(:update, socket) do
    instagram_status =
      try do
        Brando.Instagram
        |> Brando.config
        |> Keyword.get(:server_name)
        |> Process.whereis
        |> Process.alive?
      rescue
        _ -> false
      end
    mem_list =
      @info_memory
      |> :erlang.memory
      |> Keyword.values

    :erlang.send_after(@interval, self, :update)
    push socket, "update", %{total_memory: Enum.at(mem_list, 0),
                             atom_memory: Enum.at(mem_list, 2),
                             instagram_status: instagram_status}
    {:noreply, socket}
  end
end
