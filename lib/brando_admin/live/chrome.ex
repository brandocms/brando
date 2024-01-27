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
  import Brando.Gettext

  import BrandoAdmin.Utils, only: [show_modal: 2]

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Brando.pubsub(), "presence")

      {:ok,
       socket
       |> assign(:socket_connected, true)
       |> assign(:presences, %{})
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
    <div :if={@socket_connected && @presences} class="presences">
      <div
        :for={{id, presence} <- @presences}
        class="user-presence visible"
        data-user-id={id}
        data-user-url={presence.urls}
        data-user-status={presence.status}
        phx-mounted={JS.add_class("visible")}
        phx-click={JS.push("select_presence", value: %{id: id}) |> show_modal("#presence-modal")}>
        <div class="avatar">
          <Content.image image={presence.avatar} size={:thumb} />
        </div>
      </div>
      <Content.modal title={gettext("Presence details")} id="presence-modal">
        <div :if={@selected_presence}>
          <%= @selected_presence.name %><br>
          <%= @selected_presence.status %><br>
          <%= @selected_presence.last_active %><br>
          <%= @selected_presence.urls %><br>
        </div>
      </Content.modal>
    </div>
    """
  end

  def handle_event("select_presence", %{"id" => id}, socket) do
    presence = Map.fetch!(socket.assigns.presences, id)
    {:noreply, assign(socket, :selected_presence, presence)}
  end

  def handle_info(
        {_, {:presence, %{user_joined: %{user: user, metas: metas}}}},
        socket
      ) do
    last_active = metas |> Enum.map(& &1.online_at) |> Enum.max()
    urls = metas |> Enum.map(& &1.url) |> Jason.encode!()
    status = (Enum.any?(metas, & &1.active) && "online") || "idle"

    presence = %{
      id: user.id,
      name: user.name,
      status: status,
      urls: urls,
      last_active: last_active,
      avatar: user.avatar
    }

    {:noreply, assign_presence(socket, presence)}
  end

  def handle_info({_, {:presence, %{user_left: %{metas: metas, user: user}}}}, socket) do
    if metas == [] do
      presence = %{
        id: user.id,
        name: user.name,
        status: "offline",
        urls: "",
        last_active: nil,
        avatar: user.avatar
      }

      {:noreply, assign_presence(socket, presence)}
    else
      last_active = metas |> Enum.map(& &1.online_at) |> Enum.max()
      urls = metas |> Enum.map(& &1.url) |> Jason.encode!()
      status = (Enum.any?(metas, & &1.active) && "online") || "idle"

      presence = %{
        id: user.id,
        name: user.name,
        status: status,
        urls: urls,
        last_active: last_active,
        avatar: user.avatar
      }

      {:noreply, assign_presence(socket, presence)}
    end
  end

  def assign_presences(socket) do
    presences = build_presences()

    Enum.reduce(
      presences,
      socket,
      fn {_, presence}, updated_socket ->
        assign_presence(updated_socket, presence)
      end
    )
  end

  defp assign_presence(socket, presence) do
    update(socket, :presences, &Map.put(&1, presence.id, presence))
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
             urls: "",
             last_active: nil,
             avatar: user.avatar
           }}

        %{user: user, metas: metas} ->
          last_active = metas |> Enum.map(& &1.online_at) |> Enum.max()
          urls = metas |> Enum.map(& &1.url) |> Jason.encode!()
          status = (Enum.any?(metas, & &1.active) && "online") || "idle"

          {id,
           %{
             id: id,
             name: user.name,
             status: status,
             urls: urls,
             last_active: last_active,
             avatar: user.avatar
           }}
      end
    end)
  end
end
