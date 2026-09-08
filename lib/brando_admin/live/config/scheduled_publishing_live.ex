defmodule BrandoAdmin.Sites.ScheduledPublishingLive do
  @moduledoc false
  use BrandoAdmin, :live_view
  use BrandoAdmin.Toast
  use Gettext, backend: Brando.Gettext

  import Brando.Utils.Datetime
  import Phoenix.Component

  alias Brando.Publisher
  alias BrandoAdmin.Components.Workspace

  def mount(_, %{"user_token" => token}, socket) do
    if connected?(socket) do
      {:ok,
       socket
       |> assign(:socket_connected, true)
       |> assign(:timezone, Brando.timezone())
       |> assign_jobs()
       |> assign_current_user(token)
       |> set_admin_locale()}
    else
      {:ok, assign(socket, :socket_connected, false)}
    end
  end

  def render(%{socket_connected: false} = assigns) do
    ~H"""
    """
  end

  def render(assigns) do
    ~H"""
    <div class="admin-workspace publishing-workspace">
      <Workspace.header
        title={gettext("Scheduled Publishing")}
        subtitle={gettext("Review upcoming content and manage the publishing queue.")}
      >
        <button type="button" class="workspace-button" phx-click="refresh_jobs" phx-disable-with={gettext("Refreshing…")}>
          {gettext("Refresh job queue")}
        </button>
      </Workspace.header>
      <div class="scheduled-publishing-live workspace-panel">
        <header class="workspace-panel-heading">
          <div>
            <h2>{gettext("Publishing queue")}</h2><p>{gettext("Times shown in %{timezone}", timezone: @timezone)}</p>
          </div>
          <span>{ngettext("%{count} job", "%{count} jobs", length(@jobs))}</span>
        </header>
        <Workspace.empty
          :if={@jobs == []}
          title={gettext("No scheduled publications")}
          description={gettext("Choose a publishing date in an entry to add it to this queue.")}
        />
        <div
          :if={@jobs != []}
          class="workspace-table-scroll"
          tabindex="0"
          role="region"
          aria-label={gettext("Publishing queue")}
        >
          <table class="workspace-table">
            <thead>
              <tr>
                <th>{gettext("Content")}</th><th>{gettext("Status")}</th><th>{gettext("Scheduled for")}</th><th>
                  <span class="workspace-sr-only">{gettext("Actions")}</span>
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :for={job <- @jobs}>
                <td class="publishing-entry">
                  <strong>{job.meta["identifier"]["title"]}</strong>
                  <small>{gettext("Entry #%{id}", id: job.args["id"])}</small>
                </td>
                <td>
                  <span class={[
                    "workspace-badge",
                    job.state in ["scheduled", "available", "executing", "completed"] && "positive",
                    job.state in ["retryable", "discarded", "cancelled"] && "warning"
                  ]}>{job_state_label(job.state)}</span>
                </td>
                <td class="publishing-date">
                  <time datetime={DateTime.to_iso8601(job.scheduled_at)}>{format_datetime(job.scheduled_at, "%d %b %Y")}<small>{format_datetime(
                    job.scheduled_at,
                    "%H:%M %Z"
                  )}</small></time>
                </td>
                <td class="row-actions">
                  <button
                    type="button"
                    class="workspace-button quiet destructive"
                    phx-click={JS.push("delete_job", value: %{id: job.id})}
                  >{gettext("Delete job")}</button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  defp job_state_label("scheduled"), do: gettext("Scheduled")
  defp job_state_label("available"), do: gettext("Queued")
  defp job_state_label("executing"), do: gettext("Publishing")
  defp job_state_label("completed"), do: gettext("Completed")
  defp job_state_label("retryable"), do: gettext("Retrying")
  defp job_state_label("discarded"), do: gettext("Failed")
  defp job_state_label("cancelled"), do: gettext("Cancelled")
  defp job_state_label(state), do: String.capitalize(state)

  def handle_params(params, url, socket) do
    uri = URI.parse(url)

    {:noreply,
     socket
     |> assign(:params, params)
     |> assign(:uri, uri)}
  end

  def handle_event("refresh_jobs", _, socket) do
    send(self(), {:toast, gettext("Job queue refreshed")})

    {:noreply, assign_jobs(socket)}
  end

  def handle_event("delete_job", %{"id" => job_id}, socket) do
    Publisher.delete_job(job_id)
    send(self(), {:toast, gettext("Job deleted")})

    {:noreply, assign_jobs(socket)}
  end

  defp set_admin_locale(%{assigns: %{current_user: current_user}} = socket) do
    current_user.language
    |> to_string()
    |> Gettext.put_locale()

    socket
  end

  defp assign_current_user(socket, token) do
    assign_new(socket, :current_user, fn ->
      Brando.Users.get_user_by_session_token(token)
    end)
  end

  defp assign_jobs(socket) do
    {:ok, jobs} = Publisher.list_jobs()
    assign(socket, :jobs, jobs)
  end
end
