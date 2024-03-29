defmodule BrandoAdmin.AdminSocket do
  @moduledoc """
  Socket specs for System and Stats channels.
  """
  use Phoenix.Socket

  ## Channels
  channel "user:*", Brando.UserChannel
  channel "lobby", Brando.LobbyChannel
  channel "live_preview:*", Brando.LivePreviewChannel

  @doc """
  Connect socket with token
  """
  @impl true
  def connect(%{"token" => token}, socket) do
    case Brando.Users.verify_token(token) do
      {:ok, user_id} ->
        {:ok, assign(socket, :user_id, user_id)}

      {:error, _} ->
        :error
    end
  end

  def connect(_params, _socket) do
    # if we get here, we did not authenticate
    :error
  end

  # Socket id's are topics that allow you to identify all sockets for a given user:
  #
  #     def id(socket), do: "users_socket:#{socket.assigns.user_id}"
  #
  # Would allow you to broadcast a "disconnect" event and terminate
  # all active sockets and channels for a given user:
  #
  #     KoiWeb.Endpoint.broadcast("users_socket:#{user.id}", "disconnect", %{})
  #
  # Returning `nil` makes this socket anonymous.
  @impl true
  def id(_socket), do: nil
end
