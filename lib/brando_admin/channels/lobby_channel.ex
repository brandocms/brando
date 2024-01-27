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
  def join("lobby", %{"url" => url}, socket) do
    socket = assign(socket, :url, url)
    send(self(), :after_join)
    {:ok, %{}, socket}
  end

  def handle_in("user:state", %{"active" => active}, socket) do
    Brando.presence().update(socket, socket.assigns.user_id, fn state ->
      %{state | online_at: inspect(System.system_time(:second)), active: active}
    end)

    {:reply, :ok, socket}
  end

  def handle_in("user:state", %{"url" => url}, socket) do
    uri = URI.parse(url)

    Brando.presence().update(socket, socket.assigns.user_id, fn state ->
      %{state | online_at: inspect(System.system_time(:second)), url: uri.path}
    end)

    {:reply, :ok, socket}
  end

  def handle_info(:after_join, socket) do
    {:ok, _} =
      Brando.presence().track(socket, socket.assigns.user_id, %{
        online_at: inspect(System.system_time(:second)),
        active: true,
        url: socket.assigns.url
      })

    {:noreply, socket}
  end
end
