defmodule Brando.Integration.UserSocket do
  use Phoenix.Socket

  ## Channels
  channel "system:*", Brando.SystemChannel
  channel "stats", Brando.StatsChannel

  ## Transports
  transport :websocket, Phoenix.Transports.WebSocket
  transport :longpoll, Phoenix.Transports.LongPoll

  # Socket params are passed from the client and can
  # be used to verify and authenticate a user. After
  # verification, you can put default assigns into
  # the socket that will be set for all channels, ie
  #
  #     {:ok, assign(socket, :user_id, verified_user_id)}
  #
  #  To deny connection, return `:error`.
  def connect(%{"token" => token}, socket) do
    case Phoenix.Token.verify(socket, "user", token, max_age: 1209600) do
      {:ok, user_id} ->
        {:ok, assign(socket, :user, user_id)}
      {:error, _} ->
        :error
    end
  end

  def connect(_params, socket) do
    {:ok, socket}
  end

  def id(_socket), do: nil
end