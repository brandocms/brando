defmodule Brando.UserChannel do
  @moduledoc """
  Channel for user specific interaction.
  """

  use Phoenix.Channel

  intercept [
    "alert",
    "set_progress",
    "increase_progress"
  ]

  @doc """
  Join user channel for your user
  """
  def join("user:" <> user_id, _params, socket) do
    require Logger
    Logger.error inspect user_id
    user = Guardian.Phoenix.Socket.current_resource(socket)

    # with {:ok, requested_user} <- Users.get_user_by(id: user_id),
    #      {:ok, :authorized}    <- can?(user, :access, requested_user)
    # do
      socket = assign(socket, :user_id, user.id)
      # send(self(), :after_join)

      {:ok, user.id, socket}
    # else
    #   {:error, :unauthorized} ->
    #     {:error, %{reason: "ikke autorisert for denne brukerkanalen"}}
    #   {:error, {:user, :not_found}} ->
    #     {:error, %{reason: "fant ikke brukeren"}}
    # end
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
    Brando.endpoint.broadcast!("user:" <> Integer.to_string(user.id), "alert", %{message: message})
  end

  def set_progress(user, value) do
    Brando.endpoint.broadcast!("user:" <> Integer.to_string(user.id), "set_progress", %{value: value})
  end

  def increase_progress(user, value) do
    Brando.endpoint.broadcast!("user:" <> Integer.to_string(user.id), "increase_progress", %{value: value})
  end
end
