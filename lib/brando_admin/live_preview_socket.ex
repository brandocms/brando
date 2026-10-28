defmodule BrandoAdmin.LivePreviewSocket do
  @moduledoc """
  The socket a live-preview page connects to. The application's endpoint
  mounts it next to the admin socket:

      socket "/__livepreview/socket", BrandoAdmin.LivePreviewSocket,
        websocket: [check_origin: false],
        longpoll: false

  A preview page is sandboxed (`Brando.Plug.LivePreview`): its origin is
  opaque, so its WebSocket request carries `Origin: null` and none of the
  viewer's `SameSite=Lax` cookies. Phoenix's origin check would turn `null`
  away, and the admin socket (`BrandoAdmin.AdminSocket`) keeps that check.
  This socket goes without it, which is safe because it reads no cookie: it
  connects only with a token for one preview
  (`Brando.LivePreview.SocketToken`), and only that preview's
  `BrandoAdmin.LivePreviewChannel` joins it. Its id is the session's, so
  ending the session disconnects it.
  """
  use Phoenix.Socket

  channel "live_preview:*", BrandoAdmin.LivePreviewChannel

  @doc """
  The endpoint line that mounts the socket, as `mix brando.install` and
  `mix brando.migrate55` write it.
  """
  @spec endpoint_line() :: String.t()
  def endpoint_line,
    do:
      ~s(socket "/__livepreview/socket", BrandoAdmin.LivePreviewSocket, websocket: [check_origin: false], longpoll: false)

  @impl true
  def connect(params, socket, connect_info) do
    socket =
      if Application.get_env(Brando.otp_app(), :sql_sandbox, false),
        do: assign(socket, :phoenix_ecto_sandbox, connect_info[:user_agent]),
        else: socket

    Brando.Authorization.Realtime.allow_sandbox(socket)
    connect(params, socket)
  end

  # `:preview`, not `:user_id`: `BrandoAdmin.AdminSocket.session_valid?/1` is
  # false for this socket, so no admin channel would take it either.
  @impl true
  def connect(%{"token" => token}, socket) do
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

  def connect(_params, _socket), do: :error

  # The session's `Brando.Users.live_socket_id/1`
  @impl true
  def id(socket), do: socket.assigns.socket_id
end
