defmodule BrandoAdmin.Chrome do
  @moduledoc """
  A sticky live view for

      - navigation
      - presence
      - toasts (mutations and regular)
      - progress

  """

  use Phoenix.LiveView
  use Gettext, backend: Brando.Gettext

  import BrandoAdmin.Utils, only: [show_modal: 1]

  alias Brando.Utils.Datetime
  alias BrandoAdmin.Components.Content

  ##

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Brando.pubsub(), "presence")
      presences = build_presences()

      active_presences = Enum.filter(presences, &(&1.status in ["online", "idle"]))

      inactive_presences =
        presences
        |> Enum.filter(&(&1.status == "offline"))
        |> Enum.reverse()

      {:ok,
       socket
       |> assign(:socket_connected, true)
       |> stream(:active_presences, active_presences)
       |> stream(:inactive_presences, inactive_presences)}
    else
      {:ok,
       socket
       |> assign(:socket_connected, false)
       |> assign(:presences, %{})}
    end
  end

  def render(assigns) do
    ~H"""
    <div :if={@socket_connected} class="presences" phx-click={show_modal("#presence-modal")}>
      <Content.modal title={gettext("Presence details")} id="presence-modal" narrow>
        <div class="user-presence-modal">
          <p>
            {gettext("Current user activity")} &darr;
          </p>
          <div class="online" phx-update="stream" id="presence-modal-online">
            <%= for {dom_id, presence} <- @streams.active_presences do %>
              <.presence_modal_item presence={presence} id={"#{dom_id}_modal"} />
            <% end %>
          </div>
          <div class="offline" phx-update="stream" id="presence-modal-offline">
            <%= for {dom_id, presence} <- @streams.inactive_presences do %>
              <.presence_modal_item presence={presence} id={"#{dom_id}_modal"} />
            <% end %>
          </div>
        </div>
      </Content.modal>
      <div class="presences-active" id="presences-active" phx-update="stream">
        <.presence
          :for={{dom_id, presence} <- @streams.active_presences}
          presence={presence}
          id={dom_id}
        />
      </div>
      <div class="presences-inactive" id="presences-inactive" phx-update="stream">
        <.presence
          :for={{dom_id, presence} <- @streams.inactive_presences}
          presence={presence}
          id={dom_id}
        />
      </div>
    </div>
    """
  end

  def presence_modal_item(assigns) do
    last_active =
      if assigns.presence.last_active do
        assigns.presence.last_active
        |> String.to_integer()
        |> DateTime.from_unix!()
        |> DateTime.shift_zone!(Brando.timezone())
        |> Datetime.format_datetime("%d/%m/%y %H:%M:%S")
      else
        if assigns.presence.last_login do
          assigns.presence.last_login
          |> DateTime.from_naive!("Etc/UTC")
          |> DateTime.shift_zone!(Brando.timezone())
          |> Datetime.format_datetime("%d/%m/%y %H:%M:%S")
        end
      end

    assigns = assign(assigns, :last_active, last_active)

    ~H"""
    <div class="user-presence-item" id={@id}>
      <div class={["status", @presence.status]}>●</div>
      <div class="info">
        <div class="name">{@presence.name}</div>
        <div class="last-active">
          {@last_active}
        </div>
      </div>
      <div :if={@presence.urls != []} class="urls">
        <div :for={url <- @presence.urls} class="url">
          {url}
        </div>
      </div>
    </div>
    """
  end

  attr :presence, :map, required: true
  attr :id, :string, required: true

  def presence(assigns) do
    assigns =
      assign(
        assigns,
        :status,
        (assigns.presence.status in ["online", "idle"] && "online") || "offline"
      )

    ~H"""
    <div
      id={@id}
      class="user-presence"
      data-user-id={@presence.id}
      data-user-status={@presence.status}
    >
      <div class="avatar">
        <Content.image image={@presence.avatar} size={:thumb} />
      </div>
    </div>
    """
  end

  def handle_info({_, {:presence, %{user_joined: %{user: user, metas: metas}}}}, socket) do
    last_active =
      metas
      |> Enum.map(& &1.online_at)
      |> Enum.max()

    urls = Enum.map(metas, & &1.url)
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
      current_time = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

      presence = %{
        id: user.id,
        name: user.name,
        status: "offline",
        urls: [],
        last_active: nil,
        last_login: current_time,
        avatar: user.avatar
      }

      Brando.Users.set_last_login(%Brando.Users.User{id: user.id})

      {:noreply, assign_presence(socket, "offline", presence)}
    else
      last_active =
        metas
        |> Enum.map(& &1.online_at)
        |> Enum.max()

      urls = Enum.map(metas, & &1.url)
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
    |> stream_insert(:active_presences, presence, at: -1)
    |> stream_delete(:inactive_presences, presence)
  end

  defp assign_presence(socket, "idle", presence) do
    socket
    |> stream_insert(:active_presences, presence)
    |> stream_delete(:inactive_presences, presence)
  end

  defp assign_presence(socket, "offline", presence) do
    socket
    |> stream_insert(:inactive_presences, presence, at: -1)
    |> stream_delete(:active_presences, presence)
  end

  # If we ever will listen for "delete user" events
  # defp remove_presence(socket, id) do
  #   update(socket, :presences, &Map.delete(&1, id))
  # end

  defp build_presences do
    presences = Brando.presence().list("lobby")
    presence_map = Map.new(presences)
    all_users_map = Brando.Users.get_users_map()

    Enum.map(all_users_map, fn {id, user} ->
      case Map.get(presence_map, id) do
        nil ->
          %{
            id: id,
            name: user.name,
            status: "offline",
            urls: [],
            last_active: nil,
            last_login: user.last_login,
            avatar: user.avatar
          }

        %{user: user, metas: metas} ->
          last_active =
            metas
            |> Enum.map(& &1.online_at)
            |> Enum.max()

          urls = Enum.map(metas, & &1.url)
          status = (Enum.any?(metas, & &1.active) && "online") || "idle"

          %{
            id: id,
            name: user.name,
            status: status,
            urls: urls,
            last_login: user.last_login,
            last_active: last_active,
            avatar: user.avatar
          }
      end
    end)
  end
end
