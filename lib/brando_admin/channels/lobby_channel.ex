defmodule Brando.LobbyChannel do
  @moduledoc """
  Channel for all users (mostly toast updates)
  """

  use Phoenix.Channel

  # intercept([
  #   "alert",
  #   "set_progress",
  #   "increase_progress"
  # ])

  @doc """
  Join lobby channel
  """
  def join("lobby", _params, socket) do
    {:ok, %{}, socket}
  end
end
