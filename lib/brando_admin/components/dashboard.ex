defmodule BrandoAdmin.Components.Dashboard do
  @moduledoc """
  A reusable, scope-aware starting point for the admin: recently updated
  entries as cards with their cover, and drafts, scheduled publishing and
  what expires in the next two weeks in a side column.
  """
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Activity
  alias BrandoAdmin.Components.Content.List.Row
  alias BrandoAdmin.Components.Workspace

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:overview, BrandoAdmin.Dashboard.load(assigns.current_user))
     |> assign(:paused_webhooks, paused_webhooks(assigns.current_user))
     |> assign(:paused_routes, paused_routes(assigns.current_user))
     |> assign(:notifications_queue_missing?, Brando.Notifications.Routing.queue_warning?(assigns.current_user))
     |> assign(:release_changes, release_changes(assigns.current_user))
     |> assign_move(assigns.current_user)
     |> assign(:encrypted_data, encrypted_data(assigns.current_user))}
  end

  # The webhooks and notification routes paused when the database turned out
  # to come from another installation (`Brando.Crypto.Marker`), for those
  # who manage either, until one of them dismisses it
  defp assign_move(socket, user) do
    move =
      if Brando.Webhooks.can_manage?(user) or Brando.Notifications.Routing.can_manage?(user),
        do: Brando.Crypto.Marker.move_notice()

    assign(socket, :move, move)
  end

  # What this installation's secret cannot read, for those who may forget it
  # (`Brando.Crypto.Audit.forget/2`)
  defp encrypted_data(user) do
    if Brando.Authorization.Boundary.superuser?(user) do
      case Brando.Doctor.Checks.EncryptedData.run(nil) do
        %{status: :error} = result -> result
        _ -> nil
      end
    end
  end

  def handle_event("dismiss_move_notice", _params, socket) do
    user = socket.assigns.current_user

    if Brando.Webhooks.can_manage?(user) or Brando.Notifications.Routing.can_manage?(user),
      do: Brando.Crypto.Marker.dismiss_paused()

    {:noreply, assign_move(socket, user)}
  end

  @doc """
  The notice that the database came from another host, and which webhooks
  and notification routes were paused for it: each one of this site
  environment by name, linked, and how many in the others.
  """
  attr :move, :map, required: true
  attr :myself, :any, required: true

  def move_notice(assigns) do
    here = Brando.Tenant.current_prefix()
    {local, elsewhere} = Enum.split_with(assigns.move.paused, &(&1["prefix"] == here))
    count = assigns.move.paused |> Enum.map(& &1["count"]) |> Enum.sum()

    assigns =
      assign(assigns,
        local: local,
        count: count,
        elsewhere: elsewhere |> Enum.map(& &1["count"]) |> Enum.sum()
      )

    ~H"""
    <div class="dashboard-alert dashboard-move" role="alert" data-testid="dashboard-database-moved">
      <.icon name="triangle-alert" />
      <div>
        <h2>{gettext("This database came from %{host}", host: @move.from)}</h2>
        <p>
          {ngettext(
            "So that this copy calls no real endpoint, 1 webhook or notification route was paused when this installation started with it. Resume what this environment should send.",
            "So that this copy calls no real endpoint, %{count} webhooks and notification routes were paused when this installation started with it. Resume what this environment should send.",
            @count
          )}
        </p>
        <ul :if={@local != []} class="dashboard-move-paused">
          <li :for={group <- @local}>
            <span>{paused_kind(group["kind"])}:</span>
            <span class="dashboard-move-names">
              <.link :for={item <- group["named"]} navigate={paused_item_path(group["kind"], item["id"])}>
                {item["name"]}
              </.link>
            </span>
            <.link :if={group["count"] > length(group["named"])} navigate={paused_list_path(group["kind"])}>
              {gettext("and %{count} more", count: group["count"] - length(group["named"]))}
            </.link>
          </li>
        </ul>
        <p :if={@elsewhere > 0}>
          {ngettext(
            "1 of them is in another site environment.",
            "%{count} of them are in other site environments.",
            @elsewhere
          )}
        </p>
      </div>
      <button type="button" class="btn" phx-click="dismiss_move_notice" phx-target={@myself}>
        {gettext("Dismiss")}
      </button>
    </div>
    """
  end

  defp paused_kind("webhook"), do: gettext("Webhooks")
  defp paused_kind(_route), do: gettext("Notification routes")

  defp paused_item_path("webhook", id), do: "/admin/config/webhooks/#{id}/edit"
  defp paused_item_path(_route, id), do: "/admin/config/notifications/#{id}/edit"

  defp paused_list_path("webhook"), do: "/admin/config/webhooks"
  defp paused_list_path(_route), do: "/admin/config/notifications"

  @doc """
  The notice that the database holds values this installation's secret
  cannot read: the System check's result, with a link to Encrypted data,
  where they can be forgotten.
  """
  attr :result, :map, required: true

  def encrypted_data_notice(assigns) do
    ~H"""
    <div class="dashboard-alert" role="alert" data-testid="dashboard-encrypted-data">
      <.icon name="triangle-alert" />
      <div>
        <h2>{gettext("This database was encrypted with another secret")}</h2>
        <p>{Enum.join(@result.items, ", ")}</p>
        <p>{@result.fix}</p>
      </div>
      <.link navigate="/admin/config/encrypted-data" class="btn" data-testid="dashboard-encrypted-data-review">
        {gettext("Review")}
      </.link>
    </div>
    """
  end

  # The release's module definitions that aren't applied yet
  # (`Brando.Content.Definitions.ReleaseStatus`), for those who may apply
  # them (`Brando.Content.Definitions.Release.authorize/1`)
  defp release_changes(user) do
    with :ok <- Brando.Content.Definitions.Release.authorize(user),
         %{pending: pending} = changes when pending > 0 <- Brando.Content.Definitions.ReleaseStatus.summary() do
      changes
    else
      _ -> nil
    end
  end

  @doc """
  The notice that the release brings module definitions that aren't applied
  yet, with a link to Block modules → Release changes, where they are
  reviewed and applied.
  """
  attr :changes, :map, required: true

  def release_changes_notice(assigns) do
    ~H"""
    <div class="dashboard-alert" role="alert" data-testid="dashboard-release-modules">
      <.icon name="package" />
      <div>
        <h2>
          {ngettext(
            "This release has 1 module change that isn't applied yet",
            "This release has %{count} module changes that aren't applied yet",
            @changes.pending
          )}
        </h2>
        <p>
          {gettext(
            "Release %{version} brings module definitions that differ from this site's. Review what they change, then apply them.",
            version: @changes.version
          )}
        </p>
      </div>
      <.link navigate="/admin/config/content/modules/release" class="btn" data-testid="dashboard-release-modules-review">
        {gettext("Review")}
      </.link>
    </div>
    """
  end

  # Shown to the people who can do something about it.
  defp paused_webhooks(user) do
    if Brando.Webhooks.can_manage?(user), do: Brando.Webhooks.paused_after_failures(), else: []
  end

  defp paused_routes(user) do
    if Brando.Notifications.Routing.can_manage?(user),
      do: Brando.Notifications.Routing.paused_after_failures(),
      else: []
  end

  @doc """
  The notice that notifications wait for a queue that is not running: the
  application's own Oban configuration lacks `notifications`
  (`Brando.Notifications.Routing.queue_missing?/1`). Shown to those who
  manage routes.
  """
  def notifications_queue_notice(assigns) do
    ~H"""
    <div class="dashboard-alert" role="alert" data-testid="dashboard-notifications-queue">
      <.icon name="triangle-alert" />
      <div>
        <h2>{gettext("Notifications are not being sent")}</h2>
        <p>
          {gettext(
            "This site runs no notifications queue, so Slack, Teams and email notifications wait. A developer adds notifications: [limit: 2] to the Oban queues."
          )}
        </p>
      </div>
      <.link navigate="/admin/config/notifications" class="btn">{gettext("Review notifications")}</.link>
    </div>
    """
  end

  # One paused: straight to it. Several: the list.
  defp paused_path([%{id: id}], base), do: "#{base}/#{id}/edit"
  defp paused_path(_paused, base), do: base

  def render(assigns) do
    ~H"""
    <div class="admin-workspace dashboard-workspace">
      <Workspace.header title={gettext("Dashboard")} subtitle={@current_user.name} />
      <div :if={@paused_webhooks != []} class="dashboard-alert" role="alert" data-testid="dashboard-webhooks-paused">
        <.icon name="triangle-alert" />
        <div>
          <h2>
            {ngettext(
              "A webhook was paused",
              "%{count} webhooks were paused",
              length(@paused_webhooks)
            )}
          </h2>
          <p>
            {gettext("Deliveries to %{names} failed for a day. Check the receiver, then resume it.",
              names: Enum.map_join(@paused_webhooks, ", ", & &1.name)
            )}
          </p>
        </div>
        <.link navigate={paused_path(@paused_webhooks, "/admin/config/webhooks")} class="btn">
          {gettext("Review webhooks")}
        </.link>
      </div>
      <div
        :if={@paused_routes != []}
        class="dashboard-alert"
        role="alert"
        data-testid="dashboard-notifications-paused"
      >
        <.icon name="triangle-alert" />
        <div>
          <h2>
            {ngettext(
              "A notification route was paused",
              "%{count} notification routes were paused",
              length(@paused_routes)
            )}
          </h2>
          <p>
            {gettext("Messages on %{names} kept failing. Check the webhook URL, then resume it.",
              names: Enum.map_join(@paused_routes, ", ", & &1.name)
            )}
          </p>
        </div>
        <.link
          navigate={paused_path(@paused_routes, "/admin/config/notifications")}
          class="btn"
          data-testid="dashboard-notifications-review"
        >
          {gettext("Review notifications")}
        </.link>
      </div>
      <.notifications_queue_notice :if={@notifications_queue_missing?} />
      <.release_changes_notice :if={@release_changes} changes={@release_changes} />
      <.move_notice :if={@move} move={@move} myself={@myself} />
      <.encrypted_data_notice :if={@encrypted_data} result={@encrypted_data} />
      <div class="dashboard-layout">
        <section class="dashboard-recent" aria-labelledby="dashboard-recent-heading">
          <h2 id="dashboard-recent-heading" class="dashboard-heading">{gettext("Recently updated")}</h2>
          <Workspace.empty
            :if={@overview.recent == []}
            title={gettext("No recent content")}
            description={gettext("Content you have access to will appear here after it is edited.")}
          />
          <div :if={@overview.recent != []} class="dashboard-cards">
            <.entry_card :for={entry <- @overview.recent} entry={entry} />
          </div>
        </section>

        <aside class="dashboard-side">
          <section class="workspace-panel dashboard-panel" aria-labelledby="dashboard-drafts-heading">
            <header class="dashboard-panel-heading">
              <h2 id="dashboard-drafts-heading">{gettext("Drafts")}</h2>
              <span :if={@overview.drafts != []} class="dashboard-count">{length(@overview.drafts)}</span>
            </header>
            <Workspace.empty
              :if={@overview.drafts == []}
              title={gettext("No drafts")}
              description={gettext("Unpublished content you can edit will appear here.")}
            />
            <div class="dashboard-entry-list">
              <article :for={entry <- @overview.drafts} class="dashboard-entry">
                <Activity.avatar :if={entry.editor} user={entry.editor} />
                <div>
                  <.entry_title entry={entry} />
                  <small>{entry.type} · <.when_label at={entry.updated_at} /></small>
                </div>
              </article>
            </div>
          </section>

          <section class="workspace-panel dashboard-panel" aria-labelledby="dashboard-scheduled-heading">
            <header class="dashboard-panel-heading">
              <h2 id="dashboard-scheduled-heading">{gettext("Scheduled publishing")}</h2>
              <span :if={@overview.scheduled != []} class="dashboard-count">{length(@overview.scheduled)}</span>
            </header>
            <Workspace.empty
              :if={@overview.scheduled == []}
              title={gettext("Nothing scheduled")}
              description={gettext("Upcoming publications you have access to will appear here.")}
            />
            <div class="dashboard-entry-list">
              <article :for={entry <- @overview.scheduled} class="dashboard-entry">
                <.date_tile at={entry.scheduled_at} />
                <div>
                  <.link navigate={entry.path}>{entry.title}</.link>
                  <small>{entry.type} · <BrandoAdmin.Dates.time at={entry.scheduled_at} format={:long} /></small>
                </div>
              </article>
            </div>
          </section>

          <section
            class="workspace-panel dashboard-panel"
            aria-labelledby="dashboard-expiring-heading"
            data-testid="dashboard-expiring"
          >
            <header class="dashboard-panel-heading">
              <h2 id="dashboard-expiring-heading">{gettext("Expiring soon")}</h2>
              <span :if={@overview.expiring != []} class="dashboard-count">{length(@overview.expiring)}</span>
            </header>
            <Workspace.empty
              :if={@overview.expiring == []}
              title={gettext("Nothing expires soon")}
              description={gettext("Content you can edit that expires in the next 14 days will appear here.")}
            />
            <div class="dashboard-entry-list">
              <article :for={entry <- @overview.expiring} class="dashboard-entry">
                <.date_tile at={entry.at} />
                <div>
                  <.link navigate={entry.path}>{entry.title}</.link>
                  <small>{entry.type} · <BrandoAdmin.Dates.time at={entry.at} format={:long} /></small>
                </div>
              </article>
            </div>
          </section>
        </aside>
      </div>
    </div>
    """
  end

  attr :entry, :map, required: true

  # The whole card opens the entry: its title link is stretched over it.
  def entry_card(assigns) do
    ~H"""
    <article class={["dashboard-card", @entry.path && "is-linked"]}>
      <div class="dashboard-card-cover">
        <img
          :if={@entry.cover}
          src={@entry.cover.src}
          srcset={@entry.cover.srcset}
          sizes="(max-width: 600px) 92px, 300px"
          alt=""
          loading="lazy"
        />
        <.icon :if={!@entry.cover} name={@entry.icon} />
      </div>
      <div class="dashboard-card-body">
        <h3><.entry_title entry={@entry} /></h3>
        <span class="dashboard-card-type">
          <.icon name={@entry.icon} />{@entry.type}<span :if={@entry.language}>· {@entry.language}</span>
        </span>
        <div class="dashboard-card-meta">
          <span :if={@entry.status} class="dashboard-card-status">
            <Row.status_circle status={@entry.status} /><span>{Row.status_label(@entry.status)}</span>
          </span>
          <.when_label at={@entry.updated_at} />
          <Activity.avatar :if={@entry.editor} user={@entry.editor} />
        </div>
      </div>
    </article>
    """
  end

  attr :entry, :map, required: true

  defp entry_title(assigns) do
    ~H"""
    <.link :if={@entry.path} navigate={@entry.path}>{@entry.title}</.link>
    <strong :if={!@entry.path}>{@entry.title}</strong>
    """
  end

  attr :at, :any, required: true

  # `Today 14:32`, `Yesterday 09:10` or `01.10.26 17:05`
  defp when_label(assigns) do
    ~H"""
    <time :if={@at} datetime={DateTime.to_iso8601(@at)} title={BrandoAdmin.Dates.full(@at)}>
      {Activity.when_label(@at)}
    </time>
    """
  end

  attr :at, :any, required: true

  defp date_tile(assigns) do
    local = DateTime.shift_zone!(assigns.at, Brando.timezone())
    assigns = assign(assigns, day: local.day, month: month_label(local.month))

    ~H"""
    <span class="dashboard-date" aria-hidden="true"><b>{@day}</b><small>{@month}</small></span>
    """
  end

  defp month_label(month) do
    month
    |> Brando.Utils.Datetime.get_month_name(Gettext.get_locale(Brando.Gettext))
    |> String.slice(0, 3)
  end
end
