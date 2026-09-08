defmodule BrandoAdmin.Components.Dashboard do
  @moduledoc "A reusable, scope-aware starting point for the admin."
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Workspace

  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> assign(:overview, BrandoAdmin.Dashboard.load(assigns.current_user))}
  end

  def render(assigns) do
    ~H"""
    <div class="admin-workspace dashboard-workspace">
      <Workspace.header title={gettext("Dashboard")} subtitle={@current_user.name} />
      <nav :if={@overview.shortcuts != []} class="dashboard-shortcuts" aria-label={gettext("Shortcuts")}>
        <.link :for={shortcut <- @overview.shortcuts} navigate={shortcut.path} class="dashboard-shortcut">
          <.icon name={shortcut.icon} /><span>{shortcut.label}</span>
        </.link>
      </nav>
      <div class="dashboard-columns">
        <section class="workspace-panel dashboard-recent">
          <header class="workspace-panel-heading">
            <h2>{gettext("Recently updated")}</h2>
          </header>
          <Workspace.empty
            :if={@overview.recent == []}
            title={gettext("No recent content")}
            description={gettext("Content you have access to will appear here after it is edited.")}
          />
          <div class="dashboard-entry-list">
            <.entry :for={entry <- @overview.recent} entry={entry} />
          </div>
        </section>
        <div class="dashboard-secondary">
          <section class="workspace-panel">
            <header class="workspace-panel-heading">
              <h2>{gettext("Drafts")}</h2>
            </header>
            <Workspace.empty
              :if={@overview.drafts == []}
              title={gettext("No drafts")}
              description={gettext("Unpublished content you can edit will appear here.")}
            />
            <div class="dashboard-entry-list"><.entry :for={entry <- @overview.drafts} entry={entry} compact /></div>
          </section>
          <section class="workspace-panel">
            <header class="workspace-panel-heading">
              <h2>{gettext("Scheduled publishing")}</h2>
            </header>
            <Workspace.empty
              :if={@overview.scheduled == []}
              title={gettext("Nothing scheduled")}
              description={gettext("Upcoming publications you have access to will appear here.")}
            />
            <div class="dashboard-entry-list">
              <article :for={entry <- @overview.scheduled} class="dashboard-entry">
                <div><.link navigate={entry.path}>{entry.title}</.link><small>{entry.type}</small></div>
                <time datetime={DateTime.to_iso8601(entry.scheduled_at)}>{Brando.Utils.Datetime.format_datetime(
                  entry.scheduled_at,
                  "%d %b · %H:%M %Z"
                )}</time>
              </article>
            </div>
          </section>
        </div>
      </div>
    </div>
    """
  end

  attr :entry, :map, required: true
  attr :compact, :boolean, default: false

  def entry(assigns) do
    ~H"""
    <article class="dashboard-entry">
      <div>
        <.link :if={@entry.path} navigate={@entry.path}>{@entry.title}</.link>
        <strong :if={!@entry.path}>{@entry.title}</strong>
        <small>{@entry.type}<span :if={@entry.language}> · {@entry.language}</span></small>
      </div>
      <div class="dashboard-entry-meta">
        <span :if={!@compact && @entry.status} class={["workspace-badge", @entry.status == :published && "positive"]}>{status_label(
          @entry.status
        )}</span>
        <time :if={@entry.updated_at} datetime={DateTime.to_iso8601(@entry.updated_at)}>{Brando.Utils.Datetime.format_datetime(
          @entry.updated_at,
          "%d %b · %H:%M"
        )}</time>
      </div>
    </article>
    """
  end

  defp status_label(:published), do: gettext("Published")
  defp status_label(:draft), do: gettext("Draft")
  defp status_label(:pending), do: gettext("Pending")
  defp status_label(:disabled), do: gettext("Disabled")
  defp status_label(_), do: gettext("Unpublished")
end
