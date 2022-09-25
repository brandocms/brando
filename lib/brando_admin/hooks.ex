defmodule BrandoAdmin.Hooks do
  import Phoenix.LiveView
  import Phoenix.Component

  def on_mount(:urls, _, %{"user_token" => token}, socket) do
    socket =
      socket
      |> assign_current_user(token)
      |> attach_hook(:params, :handle_params, &handle_params/3)
      |> attach_hook(:form_presence, :handle_info, fn
        {_, {:uri_presence, %{user_joined: presence}}}, socket ->
          {:halt, assign_presence(socket, presence)}

        {_, {:uri_presence, %{user_left: presence}}}, socket ->
          %{user: user} = presence

          if presence.metas == [] do
            {:halt, remove_presence(socket, user)}
          else
            {:halt, socket}
          end

        %Phoenix.Socket.Broadcast{event: "presence_diff"}, socket ->
          {:halt, socket}

        _event, socket ->
          {:cont, socket}
      end)

    {:cont, socket}
  end

  def assign_current_user(socket, token) do
    assign_new(socket, :current_user, fn ->
      Brando.Users.get_user_by_session_token(token)
    end)
  end

  def handle_params(params, url, socket) do
    uri = URI.parse(url)

    socket =
      socket
      |> assign(:params, params)
      |> assign(:uri, uri)

    if connected?(socket) do
      user_id = socket.assigns.current_user.id
      Brando.presence().track_url(uri.path, user_id)
      Phoenix.PubSub.subscribe(Brando.pubsub(), "url:#{uri.path}")

      {:halt, assign_presences(socket, uri)}
    else
      {:halt, socket}
    end
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
