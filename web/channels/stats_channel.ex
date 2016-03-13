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
    :ets
  ]

  use Phoenix.Channel

  def join("stats", _auth_msg, socket) do
    send self, :update
    {:ok, socket}
  end

  def handle_info(:update, socket) do
    instagram_status =
      try do
        Brando.Instagram.Server
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

    push socket, "update", %{
      memory: %{
        total: Enum.at(mem_list, 0),
        process: Enum.at(mem_list, 1),
        atom: Enum.at(mem_list, 2),
        binary: Enum.at(mem_list, 3),
        code: Enum.at(mem_list, 4),
        ets: Enum.at(mem_list, 5)
      }
      instagram_status: instagram_status
    }

    {:noreply, socket}
  end
end
