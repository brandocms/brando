defmodule BrandoAdmin.Chrome do
  @moduledoc """
  A sticky live view for

      - navigation
      - presence
      - toasts (mutations and regular)
      - progress

  """

  use Phoenix.LiveView
  alias Phoenix.LiveView.JS
  alias BrandoAdmin.Components.Content
  use Gettext, backend: Brando.Gettext

  import BrandoAdmin.Utils, only: [show_modal: 2]

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Brando.pubsub(), "presence")

      {:ok,
       socket
       |> assign(:socket_connected, true)
       |> assign(:active_presences, %{})
       |> assign(:inactive_presences, %{})
       |> assign(:selected_presence, nil)
       |> assign_presences()}
    else
      {:ok,
       socket
       |> assign(:socket_connected, false)
       |> assign(:presences, %{})
       |> assign(:selected_presence, nil)}
    end
  end

  def render(assigns) do
    ~H"""
    <div :if={@socket_connected && @active_presences} class="presences">
      <div class="presences-active">
        <.presence
          :for={{id, presence} <- @active_presences}
          presence={presence}
          id={id}
          selected_presence={@selected_presence}
        />
      </div>
      <div class="presences-inactive">
        <.presence
          :for={{id, presence} <- @inactive_presences}
          presence={presence}
          id={id}
          selected_presence={@selected_presence}
        />
      </div>
    </div>
    """
  end

  def handle_event("select_presence", %{"id" => id}, socket) do
    presence =
      Map.fetch!(
        Map.merge(socket.assigns.inactive_presences, socket.assigns.active_presences),
        id
      )

    {:noreply, assign(socket, :selected_presence, presence)}
  end

  def handle_info(
        {_, {:presence, %{user_joined: %{user: user, metas: metas}}}},
        socket
      ) do
    last_active = metas |> Enum.map(& &1.online_at) |> Enum.max()
    urls = metas |> Enum.map(& &1.url)
    status = (Enum.any?(metas, & &1.active) && "online") || "idle"

    presence = %{
      id: user.id,
      name: user.name,
      status: status,
      urls: urls,
      last_active: last_active,
      last_login: user.last_login,
      avatar: user.avatar
    }

    {:noreply, assign_presence(socket, status, presence)}
  end

  def handle_info({_, {:presence, %{user_left: %{metas: metas, user: user}}}}, socket) do
    if metas == [] do
      presence = %{
        id: user.id,
        name: user.name,
        status: "offline",
        urls: [],
        last_active: nil,
        last_login: user.last_login,
        avatar: user.avatar
      }

      {:noreply, assign_presence(socket, "offline", presence)}
    else
      last_active = metas |> Enum.map(& &1.online_at) |> Enum.max()
      urls = metas |> Enum.map(& &1.url)
      status = (Enum.any?(metas, & &1.active) && "online") || "idle"

      presence = %{
        id: user.id,
        name: user.name,
        status: status,
        urls: urls,
        last_active: last_active,
        last_login: user.last_login,
        avatar: user.avatar
      }

      {:noreply, assign_presence(socket, status, presence)}
    end
  end

  def assign_presences(socket) do
    presences = build_presences()

    Enum.reduce(
      presences,
      socket,
      fn {_, presence}, updated_socket ->
        assign_presence(updated_socket, presence.status, presence)
      end
    )
  end

  defp assign_presence(socket, "online", presence) do
    socket
    |> update(:active_presences, &Map.put(&1, presence.id, presence))
    |> update(:inactive_presences, &Map.delete(&1, presence.id))
  end

  defp assign_presence(socket, "idle", presence) do
    socket
    |> update(:active_presences, &Map.put(&1, presence.id, presence))
    |> update(:inactive_presences, &Map.delete(&1, presence.id))
  end

  defp assign_presence(socket, "offline", presence) do
    socket
    |> update(:inactive_presences, &Map.put(&1, presence.id, presence))
    |> update(:active_presences, &Map.delete(&1, presence.id))
  end

  # If we ever will listen for "delete user" events
  # defp remove_presence(socket, id) do
  #   update(socket, :presences, &Map.delete(&1, id))
  # end

  defp build_presences do
    presences = Brando.presence().list("lobby")
    presence_map = Enum.into(presences, %{})
    all_users_map = Brando.Users.get_users_map()

    Enum.map(all_users_map, fn {id, user} ->
      case Map.get(presence_map, id) do
        nil ->
          {id,
           %{
             id: id,
             name: user.name,
             status: "offline",
             urls: [],
             last_active: nil,
             last_login: user.last_login,
             avatar: user.avatar
           }}

        %{user: user, metas: metas} ->
          last_active = metas |> Enum.map(& &1.online_at) |> Enum.max()
          urls = metas |> Enum.map(& &1.url)
          status = (Enum.any?(metas, & &1.active) && "online") || "idle"

          {id,
           %{
             id: id,
             name: user.name,
             status: status,
             urls: urls,
             last_login: user.last_login,
             last_active: last_active,
             avatar: user.avatar
           }}
      end
    end)
  end

  attr :presence, :map, required: true
  attr :id, :integer, required: true
  attr :selected_presence, :map

  def presence(assigns) do
    last_active =
      if assigns.presence.last_active do
        assigns.presence.last_active
        |> String.to_integer()
        |> DateTime.from_unix!()
        |> DateTime.shift_zone!(Brando.timezone())
        |> Brando.Utils.Datetime.format_datetime("%d/%m/%y %H:%M:%S")
      else
        nil
      end

    assigns = assign(assigns, :last_active, last_active)

    ~H"""
    <div
      class="user-presence visible"
      data-user-id={@id}
      data-user-status={@presence.status}
      phx-mounted={JS.add_class("visible")}
      phx-click={
        "select_presence"
        |> JS.push(value: %{id: @id})
        |> show_modal("#presence-modal-#{@id}")
      }
    >
      <div class="avatar">
        <Content.image image={@presence.avatar} size={:thumb} />
      </div>
    </div>
    <Content.modal title={gettext("Presence details")} id={"presence-modal-#{@id}"}>
      <div :if={@selected_presence && @selected_presence.id == @id} class="user-presence-modal">
        <div class="name"><%= @selected_presence.name %></div>
        <div class="status badge"><%= @presence.status %></div>
        <div class="urls">
          <div :for={url <- @presence.urls} class="text-mono">
            <Brando.HTML.icon name="hero-globe-alt" /> <%= url %>
          </div>
        </div>
        <div :if={@presence.status in ["online", "idle"]} class="last-active">
          <%= gettext("Last activity") %>: <%= @last_active %>
        </div>
        <div :if={@presence.status == "offline"} class="last-active">
          <%= gettext("Last logged in") %>: <%= @presence.last_login %>
        </div>
      </div>
    </Content.modal>
    """
  end
end
