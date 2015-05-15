defmodule Brando.StatsChannel do
  @moduledoc """
  Channel for system information.
  """
  @interval 1000

  use Phoenix.Channel

  def join("stats", _auth_msg, socket) do
    send self, :update
    {:ok, socket}
  end

  def handle_info(:update, socket) do
    :random.seed(:erlang.now)
    random_number = :random.uniform(10)
    :erlang.send_after(@interval, self, :update)
    push socket, "update", %{memory: random_number}
    {:noreply, socket}
  end
end