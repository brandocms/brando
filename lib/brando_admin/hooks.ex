defmodule BrandoAdmin.Hooks do
  @moduledoc false
  use Gettext, backend: Brando.Gettext

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
          # A new meta has no active field (see `LiveView.Form.Hooks`).
          Process.delete(:brando_active_field_written)
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
      {:halt, socket |> assign_uri_presence(presence) |> release_closed_tabs(presence)}
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

          updated_socket
          |> push_active_fields(presence, metas)
          |> assign_uri_presence(presence)
          |> replay_dirty_fields(presence, latest_meta)
      end
    )
  end

  # The fields another editor's tabs are in, for a form that just opened.
  defp push_active_fields(%{assigns: %{current_user: %{id: user_id}}} = socket, %{user: %{id: user_id}}, _metas),
    do: socket

  defp push_active_fields(socket, presence, metas) do
    for %{active_field: field} = meta when is_binary(field) <- metas, reduce: socket do
      socket -> push_event(socket, "b:set_active_field", %{user_id: presence.user.id, field: field, tab: meta[:tab]})
    end
  end

  # A tab of a user who still has others here closed: its field lock goes,
  # theirs stay. Updating a tab's meta (moving to another field) is a leave
  # and a join of the same tab, which is still among `metas`, so this never
  # undoes the field it moved to.
  defp release_closed_tabs(socket, presence) do
    open = MapSet.new(presence.metas, &Map.get(&1, :tab))

    for %{tab: tab} <- Map.get(presence, :left, []), tab != nil, not MapSet.member?(open, tab), reduce: socket do
      socket -> push_event(socket, "b:set_active_field", %{user_id: presence.user.id, field: nil, tab: tab})
    end
  end

  defp replay_dirty_fields(%{assigns: %{current_user: %{id: user_id}}} = socket, %{user: %{id: user_id}}, _meta),
    do: socket

  defp replay_dirty_fields(socket, presence, meta) do
    case Map.get(meta, :dirty_fields) do
      [_ | _] = fields -> push_dirty_fields(socket, presence.user.id, fields)
      _ -> socket
    end
  end

  @doc """
  Pushes another editor's unsaved fields (input names such as `page[title]`)
  to the form, which marks them. An empty list clears that editor's marks.
  """
  def push_dirty_fields(socket, user_id, fields) do
    label =
      case socket.assigns[:presences] do
        %{^user_id => %{name: name}} when is_binary(name) -> gettext("Unsaved changes by %{name}", name: name)
        _ -> gettext("Unsaved changes by another user")
      end

    push_event(socket, "b:set_dirty_fields", %{user_id: user_id, fields: fields, label: label})
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
