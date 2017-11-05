defmodule <%= application_module %>Web.AdminSocket do
  @moduledoc """
  Socket specs for System and Stats channels.
  """
  use Phoenix.Socket
  import Guardian.Phoenix.Socket

  ## Channels
  channel "admin", <%= application_module %>.AdminChannel
  channel "user:*", Brando.UserChannel

  ## Transports
  transport :websocket, Phoenix.Transports.WebSocket
  transport :longpoll, Phoenix.Transports.LongPoll

  @doc """
  Connect socket with token
  """
  def connect(%{"guardian_token" => jwt}, socket) do
    case sign_in(socket, jwt) do
      {:ok, authed_socket, _guardian_params} ->
        {:ok, authed_socket}
      _ ->
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
  #     ByHands.Web.Endpoint.broadcast("users_socket:#{user.id}", "disconnect", %{})
  #
  # Returning `nil` makes this socket anonymous.
  def id(_socket), do: nil
end
