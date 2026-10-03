defmodule BrandoAdmin.Hooks do
  @moduledoc false
  import Phoenix.Component
  import Phoenix.LiveView

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

  def handle_params(params, url, %{assigns: %{current_user: user}} = socket) when not is_nil(user) do
    uri = URI.parse(url)
    user_id = user.id

    socket =
      socket
      |> assign(:params, params)
      |> assign(:uri, uri)
      |> default_page_title(uri, user)

    if connected?(socket) do
      # A view can be present at another view's URL: the frontend editor
      # tracks itself at the admin form of the entry it edits (see
      # `BrandoAdmin.FrontendEdit.EditorLive`).
      path = socket.assigns[:presence_path] || uri.path
      previous = socket.assigns[:previous_presence_path]

      if previous && previous != path do
        Brando.presence().untrack_url(previous, user_id)
        Phoenix.PubSub.unsubscribe(Brando.pubsub(), Brando.Tenant.Topic.scoped("url:#{previous}"))
      end

      socket =
        if previous == path do
          socket
        else
          Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.Tenant.Topic.scoped("url:#{path}"))
          Brando.presence().track_url(path, user_id, socket.assigns[:presence_meta] || %{})
          assign_uri_presences(socket, path)
        end

      {:cont, assign(socket, previous_uri: uri, previous_presence_path: path)}
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

  # A screen without a title of its own takes the name of its menu item, so
  # the browser tab doesn't just say "Admin". Screens that set `:page_title`
  # (listings, forms) keep theirs.
  defp default_page_title(%{assigns: %{page_title: title}} = socket, _uri, _user) when not is_nil(title),
    do: socket

  defp default_page_title(socket, %URI{path: path}, user) when is_binary(path) do
    case menu_title(BrandoAdmin.Menu.get_menu(user, socket.assigns[:current_site]), path) do
      nil -> socket
      title -> assign(socket, :page_title, title)
    end
  end

  defp default_page_title(socket, _uri, _user), do: socket

  @doc false
  # The name of the menu item whose URL is `path`, or, failing that, the
  # item whose URL is the longest leading part of it ("/admin" only matches
  # itself).
  def menu_title(sections, path) do
    items = sections |> Enum.flat_map(&Map.get(&1, :items, [])) |> flatten_items()

    exact = Enum.find(items, &(url_path(&1.url) == path))

    best =
      exact ||
        items
        |> Enum.filter(fn %{url: url} ->
          url_path = url_path(url)
          url_path not in [nil, "/admin"] and String.starts_with?(path, url_path <> "/")
        end)
        |> Enum.max_by(&String.length(url_path(&1.url)), fn -> nil end)

    best && to_string(best.name)
  end

  defp flatten_items(items) do
    Enum.flat_map(items, fn item ->
      children = item |> Map.get(:items) |> List.wrap()
      if Map.get(item, :url), do: [item | flatten_items(children)], else: flatten_items(children)
    end)
  end

  defp url_path(nil), do: nil
  defp url_path(url), do: url |> URI.parse() |> Map.get(:path)

  def handle_info({_, {:uri_presence, %{user_joined: presence}}}, socket) do
    {:halt, assign_uri_presence(socket, presence)}
  end

  def handle_info({_, {:uri_presence, %{user_left: presence}}}, socket) do
    %{user: user} = presence

    if presence.metas == [] do
      {:halt, remove_presence(socket, user)}
    else
      # Another of the user's sessions is still here, perhaps in a different
      # place (the admin form or the website).
      {:halt, assign_uri_presence(socket, presence)}
    end
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    # Swallow presence_diff events
    {:halt, socket}
  end

  def handle_info(_event, socket) do
    {:cont, socket}
  end

  defp assign_uri_presences(socket, path) do
    socket = assign(socket, presences: %{}, presence_ids: %{})

    Enum.reduce(
      Brando.presence().list(Brando.Tenant.Topic.scoped("url:#{path}")),
      socket,
      fn
        {_, %{user: nil}}, updated_socket ->
          updated_socket

        {_, %{metas: []}}, updated_socket ->
          updated_socket

        {_, presence}, updated_socket ->
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

  defp assign_uri_presence(socket, %{user: nil}), do: socket

  defp assign_uri_presence(socket, presence) do
    %{user: user} = presence
    metas = Map.get(presence, :metas, [])

    # Someone editing only from the website is shown as such; any admin
    # session at the URL counts as being in the admin.
    user = Map.put(user, :frontend?, metas != [] and Enum.all?(metas, &(Map.get(&1, :frontend) == true)))

    socket
    |> update(:presences, &Map.put(&1, user.id, user))
    |> update(:presence_ids, &Map.put_new(&1, user.id, System.system_time()))
  end

  defp remove_presence(socket, nil), do: socket

  defp remove_presence(socket, user) do
    socket
    |> update(:presences, &Map.delete(&1, user.id))
    |> update(:presence_ids, &Map.delete(&1, user.id))
    |> push_event("b:clear_user_presence", %{user_id: user.id})
  end
end
