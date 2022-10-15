defmodule BrandoAdmin.Hooks do
  import Phoenix.LiveView
  import Phoenix.Component

  def on_mount(:urls, _, %{"user_token" => token}, socket) do
    socket =
      socket
      |> assign_current_user(token)
      |> attach_hook(:params, :handle_params, &handle_params/3)
      |> attach_hook(:form_presence, :handle_info, &handle_info/2)

    {:cont, socket}
  end

  def assign_current_user(socket, token) do
    assign_new(socket, :current_user, fn ->
      Brando.Users.get_user_by_session_token(token)
    end)
  end

  def handle_params(params, url, socket) do
    uri = URI.parse(url)
    user_id = socket.assigns.current_user.id

    socket =
      socket
      |> assign(:params, params)
      |> assign(:uri, uri)

    if connected?(socket) do
      if socket.assigns[:previous_uri] do
        require Logger
        Logger.error("== untracking #{uri.path} for user #{user_id}")
        Brando.presence().untrack_url(socket.assigns.previous_uri, user_id)
      end

      socket = assign(socket, :previous_uri, uri)

      require Logger
      Logger.error("== tracking #{uri.path} for user #{user_id}")
      Phoenix.PubSub.subscribe(Brando.pubsub(), "url:#{uri.path}")
      Brando.presence().track_url(uri.path, user_id)

      {:halt, assign_presences(socket, uri)}
    else
      {:halt, socket}
    end
  end

  def handle_info({_, {:uri_presence, %{user_joined: presence}}}, socket) do
    require Logger
    Logger.error("== uri_presence: user_joined")
    {:halt, assign_presence(socket, presence)}
  end

  def handle_info({_, {:uri_presence, %{user_left: presence}}}, socket) do
    require Logger
    Logger.error("== uri_presence: user_joined")
    %{user: user} = presence

    if presence.metas == [] do
      {:halt, remove_presence(socket, user)}
    else
      {:halt, socket}
    end
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:halt, socket}
  end

  def handle_info(_event, socket) do
    {:cont, socket}
  end

  defp assign_presences(socket, uri) do
    socket = assign(socket, presences: %{}, presence_ids: %{})

    Enum.reduce(
      Brando.presence().list("url:#{uri.path}"),
      socket,
      fn {_, presence}, acc ->
        assign_presence(acc, presence)
      end
    )
  end

  defp assign_presence(socket, presence) do
    %{user: user} = presence
    %{presence_ids: presence_ids} = socket.assigns

    cond do
      Map.has_key?(presence_ids, user.id) ->
        socket

      true ->
        socket
        |> update(:presences, &Map.put(&1, user.id, user))
        |> update(:presence_ids, &Map.put(&1, user.id, System.system_time()))
    end
  end

  defp remove_presence(socket, user) do
    socket
    |> update(:presences, &Map.delete(&1, user.id))
    |> update(:presence_ids, &Map.delete(&1, user.id))
  end
end
