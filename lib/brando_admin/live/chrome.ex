defmodule BrandoAdmin.Chrome do
  @moduledoc """
  A sticky live view for

      - navigation
      - presence
      - toasts (mutations and regular)
      - progress

  """

  use BrandoAdmin, :child_live_view
  use Gettext, backend: Brando.Gettext

  import BrandoAdmin.Utils, only: [show_modal: 1]

  alias Brando.Utils.Datetime
  alias BrandoAdmin.Components.Content

  alias Brando.Authorization.{Realtime, Scope}

  on_mount {BrandoAdmin.UserAuth, :mount_current_user}
  on_mount {Brando.Tenant.LiveView, :default}
  on_mount {BrandoAdmin.Authorization, :default}

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Brando.pubsub(), "presence")
      {:ok, socket |> assign(:socket_connected, true) |> refresh_authorization()}
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
        <.presence :for={{dom_id, presence} <- @streams.active_presences} presence={presence} id={dom_id} />
      </div>
      <div class="presences-inactive" id="presences-inactive" phx-update="stream">
        <.presence :for={{dom_id, presence} <- @streams.inactive_presences} presence={presence} id={dom_id} />
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
        if assigns.presence.last_seen do
          assigns.presence.last_seen
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
    <div id={@id} class="user-presence" data-user-id={@presence.id} data-user-status={@presence.status}>
      <div class="avatar">
        <Content.image image={@presence.avatar} size={:thumb} />
      </div>
    </div>
    """
  end

  def handle_info({_, {:presence, _}}, socket), do: {:noreply, refresh_authorization(socket)}

  def refresh_authorization(socket) do
    scope = socket.assigns[:authorization_scope] || Scope.current(socket.assigns.current_user)
    presences = build_presences(scope)
    {active, inactive} = Enum.split_with(presences, &(&1.status in ["online", "idle"]))

    socket
    |> stream(:active_presences, active, reset: true)
    |> stream(:inactive_presences, Enum.reverse(inactive), reset: true)
  end

  def assign_presences(socket), do: refresh_authorization(socket)

  defp build_presences(scope) do
    presence_map = Map.new(Brando.presence().list("lobby"))

    Enum.map(Realtime.users(scope), fn user ->
      metas =
        presence_map
        |> Map.get(user.id, %{metas: []})
        |> Map.get(:metas, [])
        |> Enum.filter(&Realtime.visible_meta?(scope, &1))

      %{
        id: user.id,
        name: user.name,
        avatar: user.avatar,
        status:
          cond do
            metas == [] -> "offline"
            Enum.any?(metas, & &1.active) -> "online"
            true -> "idle"
          end,
        urls: metas |> Enum.map(& &1.url) |> Enum.uniq(),
        last_active: metas |> Enum.map(& &1.online_at) |> Enum.max(fn -> nil end),
        # Global timestamps must not reveal this person's activity in other sites.
        last_login: if(scope.kind == :standalone, do: user.last_login),
        last_seen: if(scope.kind == :standalone, do: user.last_seen)
      }
    end)
  end
end
