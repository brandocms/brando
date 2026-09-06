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

  @impl true
  def connect(%{"token" => token}, socket) do
    with {:ok, user_id} <- Brando.Users.verify_token(token),
         :ok <- Brando.Authorization.Realtime.authorize_account(user_id) do
      {:ok, assign(socket, :user_id, user_id)}
    else
      _ -> :error
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
  def id(socket), do: "brando_admin_socket:#{socket.assigns.user_id}"
end
