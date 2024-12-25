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

  def on_mount(:urls, _params, _session, socket) do
    {:cont, socket}
  end

  def assign_current_user(socket, token) do
    assign_new(socket, :current_user, fn ->
      Brando.Users.get_user_by_session_token(token)
    end)
  end

  def handle_params(params, url, %{assigns: %{current_user: user}} = socket)
      when not is_nil(user) do
    uri = URI.parse(url)
    user_id = user.id

    socket =
      socket
      |> assign(:params, params)
      |> assign(:uri, uri)

    if connected?(socket) do
      if socket.assigns[:previous_uri] do
        Brando.presence().untrack_url(socket.assigns.previous_uri, user_id)
      end

      socket = assign(socket, :previous_uri, uri)
      Phoenix.PubSub.subscribe(Brando.pubsub(), "url:#{uri.path}")
      Brando.presence().track_url(uri.path, user_id)

      {:cont, assign_uri_presences(socket, uri)}
    else
      {:cont, socket}
    end
  end

  def handle_params(params, url, socket) do
    uri = URI.parse(url)

    socket =
      socket
      |> assign(:params, params)
      |> assign(:uri, uri)

    {:cont, socket}
  end

  def handle_info({_, {:uri_presence, %{user_joined: presence}}}, socket) do
    {:halt, assign_uri_presence(socket, presence)}
  end

  def handle_info({_, {:uri_presence, %{user_left: presence}}}, socket) do
    %{user: user} = presence

    if presence.metas == [] do
      {:halt, remove_presence(socket, user)}
    else
      {:halt, socket}
    end
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    # Swallow presence_diff events
    {:halt, socket}
  end

  def handle_info(_event, socket) do
    {:cont, socket}
  end

  defp assign_uri_presences(socket, uri) do
    socket = assign(socket, presences: %{}, presence_ids: %{})

    Enum.reduce(
      Brando.presence().list("url:#{uri.path}"),
      socket,
      fn {_, presence}, updated_socket ->
        # get metas
        metas = Map.get(presence, :metas)
        # find the meta with the latest last_active value
        latest_meta = Enum.max_by(metas, &Map.get(&1, :last_active))

        updated_socket =
          if Map.get(latest_meta, :active_field) do
            push_event(updated_socket, "b:set_active_field", %{
              user_id: presence.user.id,
              field: latest_meta.active_field
            })
          else
            updated_socket
          end

        assign_uri_presence(updated_socket, presence)
      end
    )
  end

  defp assign_uri_presence(socket, presence) do
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
