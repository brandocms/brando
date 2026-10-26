defmodule BrandoAdmin.AdminSocket do
  @moduledoc """
  Socket specs for System and Stats channels.
  """
  use Phoenix.Socket

  ## Channels
  channel "user:*", BrandoAdmin.UserChannel
  channel "lobby", BrandoAdmin.LobbyChannel
  channel "live_preview:*", BrandoAdmin.LivePreviewChannel

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
  #
  # A live-preview document connects with a token for one preview instead
  # (`Brando.LivePreview.SocketToken`), as its page holds editor markup. That
  # socket assigns `:preview`, not `:user_id`, so `session_valid?/1` is false
  # for it and only `BrandoAdmin.LivePreviewChannel` joins it, for its key.
  @impl true
  def connect(%{"token" => token}, socket) do
    case Brando.Users.verify_socket_token(token) do
      {:ok, session} ->
        if Brando.Authorization.Realtime.authorize_account(session.user_id) == :ok,
          do:
            {:ok, assign(socket, user_id: session.user_id, session_id: session.session_id, socket_id: session.socket_id)},
          else: :error

      {:error, _} ->
        connect_preview(token, socket)
    end
  end

  def connect(_params, _socket) do
    # if we get here, we did not authenticate
    :error
  end

  defp connect_preview(token, socket) do
    with {:ok, preview} <- Brando.LivePreview.SocketToken.verify(token),
         :ok <- Brando.Authorization.Realtime.authorize_account(preview.user_id) do
      {:ok,
       assign(socket,
         preview: Map.take(preview, [:key, :user_id, :tenant]),
         session_id: preview.session_id,
         socket_id: preview.socket_id
       )}
    else
      _ -> :error
    end
  end

  # The session's `Brando.Users.live_socket_id/1`
  @impl true
  def id(socket), do: socket.assigns.socket_id

  @doc """
  Whether the session the socket connected with is still valid. The
  channels check it as they join: the socket only subscribes to its id
  after `connect/2`, so a session ended in between would go unnoticed.
  Always false for a live-preview socket, which has no `:user_id`.
  """
  @spec session_valid?(Phoenix.Socket.t()) :: boolean()
  def session_valid?(socket), do: Brando.Users.session_valid?(socket.assigns[:session_id], socket.assigns[:user_id])
end
