defmodule Brando.StatsChannel do
  @moduledoc """
  Channel for system information.
  """
  @default_interval 5000
  @info_memory [
    :total,
    :system,
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
    interval = Brando.config(:stats_polling_interval) || @default_interval

    instagram_status = is_alive?(Brando.Instagram.Server)
    registry_status = is_alive?(Brando.Registry)

    mem_list =
      @info_memory
      |> :erlang.memory
      |> Keyword.values

    :erlang.send_after(interval, self, :update)

    push socket, "update", %{
      memory: %{
        total: Enum.at(mem_list, 0),
        system: Enum.at(mem_list, 1),
        process: Enum.at(mem_list, 2),
        atom: Enum.at(mem_list, 3),
        binary: Enum.at(mem_list, 4),
        code: Enum.at(mem_list, 5),
        ets: Enum.at(mem_list, 6)
      },
      status: %{
        instagram: instagram_status,
        registry: registry_status,
        uptime: system_uptime
      },
      interval: interval
    }

    {:noreply, socket}
  end

  defp is_alive?(module) do
    try do
      module
      |> Process.whereis
      |> Process.alive?
    rescue
      _ -> false
    end
  end

  defp system_uptime do
    :erlang.statistics(:wall_clock)
    |> elem(0)
    |> Brando.Utils.human_time
  end
end
