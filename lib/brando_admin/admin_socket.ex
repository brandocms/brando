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
  def connect(params, socket, connect_info) do
    socket =
      if Application.get_env(Brando.otp_app(), :sql_sandbox, false),
        do: assign(socket, :phoenix_ecto_sandbox, connect_info[:user_agent]),
        else: socket

    Brando.Authorization.Realtime.allow_sandbox(socket)
    connect(params, socket)
  end

  # The token names the user's session (`Brando.Users.build_socket_token/2`):
  # the socket connects only while that session lasts, and its id is the
  # session's, so ending the session — logging out, revoking it, a password
  # change, a two-factor reset, deactivating the account — disconnects it
  # with the session's LiveViews (`Brando.Users.disconnect_session/1`), and
  # its reconnects are turned away. The user's other sessions keep theirs.
  @impl true
  def connect(%{"token" => token}, socket) do
    with {:ok, session} <- Brando.Users.verify_socket_token(token),
         :ok <- Brando.Authorization.Realtime.authorize_account(session.user_id) do
      {:ok, assign(socket, user_id: session.user_id, session_id: session.session_id, socket_id: session.socket_id)}
    else
      _ -> :error
    end
  end

  def connect(_params, _socket) do
    # if we get here, we did not authenticate
    :error
  end

  # The session's `Brando.Users.live_socket_id/1`
  @impl true
  def id(socket), do: socket.assigns.socket_id
end
