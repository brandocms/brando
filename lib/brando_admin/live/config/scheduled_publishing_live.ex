defmodule BrandoAdmin.Sites.ScheduledPublishingLive do
  @moduledoc false
  use BrandoAdmin, :live_view
  use BrandoAdmin.Toast
  use Gettext, backend: Brando.Gettext

  import Brando.Utils.Datetime
  import Phoenix.Component

  alias Brando.Publisher
  alias BrandoAdmin.Components.Content

  def mount(_, %{"user_token" => token}, socket) do
    if connected?(socket) do
      {:ok,
       socket
       |> assign(:socket_connected, true)
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
    <Content.header
      title={gettext("Scheduled Publishing")}
      subtitle={gettext("Manage and clear publishing queue")}
    />

    <div class="scheduled-publishing-live">
      <p class="help">
        {gettext("A list of upcoming publisher queue jobs.")}
      </p>

      <table>
        <%= for job <- @jobs do %>
          <tr>
            <td class="state fit">
              <svg xmlns="http://www.w3.org/2000/svg" width="15" height="15" viewBox="0 0 15 15">
                <circle class={job.state} r="7.5" cy="7.5" cx="7.5" />
              </svg>
              #{job.id}
            </td>
            <td>
              <strong>{job.meta["identifier"]["title"]}</strong> <br />
              <small>{job.meta["identifier"]["type"]}#{job.meta["identifier"]["id"]}</small>
            </td>
            <td class="fit date">
              {format_datetime(job.scheduled_at, "%d/%m/%y")}
              <span>•</span> {format_datetime(job.scheduled_at, "%H:%M")}
            </td>
            <td class="fit">
              <button
                type="button"
                class="primary small"
                phx-click={JS.push("delete_job", value: %{id: job.id})}
              >
                {gettext("Delete job")}
              </button>
            </td>
          </tr>
        <% end %>
      </table>

      <button type="button" class="primary" phx-click={JS.push("refresh_jobs")}>
        {gettext("Refresh job queue")}
      </button>
    </div>
    """
  end

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
