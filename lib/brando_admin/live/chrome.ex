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

  # Socket tokens are verified with a 24h max_age; refreshed well inside it
  @socket_tokens_interval :timer.hours(6)

  def mount(_params, session, socket) do
    # Without a user, its session has just ended: the page's own LiveView
    # sends it to log in, and this one shows nothing meanwhile.
    if connected?(socket) and socket.assigns.current_user do
      Phoenix.PubSub.subscribe(Brando.pubsub(), "presence")

      {:ok,
       socket
       |> assign(:socket_connected, true)
       # The row id rather than the token, which stays out of this view's state
       |> assign(:session_id, Brando.Users.token_id(session["user_token"]))
       |> refresh_authorization()
       |> push_socket_tokens()}
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
  def handle_info(:push_socket_tokens, socket), do: {:noreply, push_socket_tokens(socket)}

  # The admin socket (presence, toasts, progress) authenticates with tokens
  # rendered into the page's meta tags at load. A tab open longer than their
  # max_age could not reconnect after a server restart, and dropped out of
  # presence until reloaded. This view authenticates with the session instead,
  # and remounts after a restart, so it hands the page fresh tokens: on every
  # mount, and every few hours while it stays up.
  defp push_socket_tokens(socket) do
    Process.send_after(self(), :push_socket_tokens, @socket_tokens_interval)
    user = socket.assigns.current_user

    case socket.assigns.session_id do
      nil ->
        socket

      session_id ->
        push_event(socket, "brando:socket_tokens", %{
          user_token: Brando.Users.build_socket_token(user, session_id),
          realtime_scope: Brando.Authorization.Realtime.token(user)
        })
    end
  end

  def refresh_authorization(socket) do
    scope = socket.assigns[:authorization_scope] || Scope.current(socket.assigns.current_user)
    presences = build_presences(scope)
    {active, inactive} = Enum.split_with(presences, &(&1.status in ["online", "idle"]))

    # Your own avatar always leads the strip; everyone else keeps their order.
    current_user_id = socket.assigns.current_user.id
    active = Enum.sort_by(active, &(&1.id != current_user_id))

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
