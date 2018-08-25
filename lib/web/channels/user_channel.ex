defmodule Brando.UserChannel do
  @moduledoc """
  Channel for user specific interaction.
  """

  use Phoenix.Channel

  intercept([
    "alert",
    "set_progress",
    "increase_progress"
  ])

  @doc """
  Join user channel for your user
  """
  def join("user:" <> _user_id, _params, socket) do
    user = Guardian.Phoenix.Socket.current_resource(socket)
    socket = assign(socket, :user_id, user.id)
    {:ok, user.id, socket}
  end

  def handle_out("alert", payload, socket) do
    push socket, "alert", payload
    {:noreply, socket}
  end

  def handle_out("set_progress", payload, socket) do
    push socket, "set_progress", payload
    {:noreply, socket}
  end

  def handle_out("increase_progress", payload, socket) do
    push socket, "increase_progress", payload
    {:noreply, socket}
  end

  def alert(user, message) do
    Brando.endpoint().broadcast!("user:" <> Integer.to_string(user.id), "alert", %{
      message: message
    })
  end

  def set_progress(user, value) do
    Brando.endpoint().broadcast!("user:" <> Integer.to_string(user.id), "set_progress", %{
      value: value
    })
  end

  def increase_progress(user, value) do
    Brando.endpoint().broadcast!("user:" <> Integer.to_string(user.id), "increase_progress", %{
      value: value
    })
  end
end
