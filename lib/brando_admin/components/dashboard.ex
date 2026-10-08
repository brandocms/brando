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
     |> assign(:notifications_queue_missing?, Brando.Notifications.Routing.queue_warning?(assigns.current_user))}
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
      <.link navigate="/admin/config/notifications" class="workspace-button">{gettext("Review notifications")}</.link>
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
        <.link navigate={paused_path(@paused_webhooks, "/admin/config/webhooks")} class="workspace-button">
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
          class="workspace-button"
          data-testid="dashboard-notifications-review"
        >
          {gettext("Review notifications")}
        </.link>
      </div>
      <.notifications_queue_notice :if={@notifications_queue_missing?} />
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
