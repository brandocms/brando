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
          <div class="online" id="presence-modal-online">
            <%= for presence <- @active_presences do %>
              <.presence_modal_item presence={presence} id={"presence-modal-user-#{presence.id}"} />
            <% end %>
          </div>
          <div class="offline" id="presence-modal-offline">
            <%= for presence <- @inactive_presences do %>
              <.presence_modal_item presence={presence} id={"presence-modal-user-#{presence.id}"} />
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
        |> BrandoAdmin.Dates.short()
      else
        if assigns.presence.last_seen do
          assigns.presence.last_seen
          |> BrandoAdmin.Dates.short()
        end
      end

    assigns = assign(assigns, :last_active, last_active)

    ~H"""
    <div class="user-presence-item" id={@id}>
      <div class="info">
        <span class={["name", "status-label", @presence.status]}>
          <svg
            class="status-dot"
            xmlns="http://www.w3.org/2000/svg"
            width="12"
            height="12"
            viewBox="0 0 12 12"
            aria-hidden="true"
          >
            <circle r="6" cy="6" cx="6" />
          </svg>
          {@presence.name}
        </span>
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
        <Content.user_avatar user={@presence} />
      </div>
    </div>
    """
  end

  def handle_info({_, {:presence, _}}, socket), do: {:noreply, refresh_authorization(socket)}

  def refresh_authorization(socket) do
    scope = socket.assigns[:authorization_scope] || Scope.current(socket.assigns.current_user)
    presences = build_presences(scope)
    {active, inactive} = Enum.split_with(presences, &(&1.status in ["online", "idle"]))

    # Realtime.users/1 answers "who may be seen", not "in what order", so it has
    # no order_by and Repo.all hands back heap order. Reversing that just gave a
    # different arbitrary order. Sort on the value actually rendered instead.
    inactive = Enum.sort_by(inactive, & &1.last_seen, &sort_recent_first/2)

    socket
    |> assign(:active_presences, active)
    |> assign(:inactive_presences, inactive)
    |> stream(:active_presences, active, reset: true)
    # The avatar strip overlaps its avatars and lays them out with row-reverse,
    # so the most recent must come last in the DOM to sit leftmost and on top.
    |> stream(:inactive_presences, Enum.reverse(inactive), reset: true)
  end

  # Most recently seen first; never-seen users sort last rather than first.
  defp sort_recent_first(nil, nil), do: true
  defp sort_recent_first(nil, _b), do: false
  defp sort_recent_first(_a, nil), do: true
  defp sort_recent_first(a, b), do: NaiveDateTime.compare(a, b) != :lt

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
