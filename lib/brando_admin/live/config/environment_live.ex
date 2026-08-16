defmodule BrandoAdmin.Sites.EnvironmentLive do
  @moduledoc false

  use BrandoAdmin, :live_view
  use BrandoAdmin.Toast
  use Gettext, backend: Brando.Gettext

  alias Brando.Environments
  alias Brando.Environments.Environment
  alias Brando.Tenant
  alias Brando.Tenant.Registry
  alias Brando.Worker.EnvironmentCopy
  alias Brando.Worker.EnvironmentSetLive
  alias BrandoAdmin.Components.Content

  @manager_roles [:admin, :superuser]

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if connected?(socket) do
      can_manage? = socket.assigns.current_user.role in @manager_roles

      {:ok,
       socket
       |> assign(:socket_connected, true)
       |> assign(:can_manage?, can_manage?)
       |> assign(:tenancy_enabled?, Tenant.enabled?())
       |> assign(:default_scheduled_at, default_scheduled_at())
       |> refresh_data()}
    else
      {:ok, assign(socket, :socket_connected, false)}
    end
  end

  @impl Phoenix.LiveView
  def render(%{socket_connected: false} = assigns) do
    ~H"""
    """
  end

  def render(assigns) do
    ~H"""
    <Content.header
      title={gettext("Environments")}
      subtitle={gettext("Create, copy, promote, schedule, and recover isolated content environments")}
    >
      <button type="button" class="secondary" phx-click="refresh">
        {gettext("Refresh")}
      </button>
    </Content.header>

    <div class="environment-management-live">
      <div :if={!@tenancy_enabled?} class="environment-notice warning">
        {gettext("Tenancy is disabled. Set tenancy_mode to single or multi before managing environments.")}
      </div>

      <div :if={@tenancy_enabled? && is_nil(@site)} class="environment-notice warning">
        {gettext("No site and live environment could be resolved for this admin session.")}
      </div>

      <div :if={@site && !@can_manage?} class="environment-notice warning">
        {gettext("Only administrators and superusers can change environment lifecycle state.")}
      </div>

      <%= if @site do %>
        <section class="environment-panel environment-overview">
          <header>
            <div>
              <h2>{@site.name}</h2>
              <p>{gettext("Schema prefix: tenant_%{site}_<environment>", site: @site.key)}</p>
            </div>
            <span class="environment-count">
              {ngettext("%{count} environment", "%{count} environments", length(@environments))}
            </span>
          </header>

          <div class="environment-table-wrap">
            <table>
              <thead>
                <tr>
                  <th>{gettext("Environment")}</th>
                  <th>{gettext("Domain")}</th>
                  <th>{gettext("State")}</th>
                  <th>{gettext("Actions")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={environment <- @environments} id={"environment-#{environment.id}"}>
                  <td>
                    <strong>{environment.name}</strong>
                    <code>{environment.key}</code>
                  </td>
                  <td>{environment.domain || "—"}</td>
                  <td>
                    <span class={["environment-state", environment.live && "live"]}>
                      {if environment.live, do: gettext("Live"), else: gettext("Working")}
                    </span>
                  </td>
                  <td class="environment-actions">
                    <button
                      :if={!environment.live}
                      type="button"
                      class="secondary small"
                      disabled={!@can_manage?}
                      phx-click="queue_set_live"
                      phx-value-id={environment.id}
                      phx-confirm={
                        gettext("Archive the current live environment and promote %{name}?", name: environment.name)
                      }
                    >
                      {gettext("Set live")}
                    </button>
                    <button
                      :if={!environment.live}
                      type="button"
                      class="danger small"
                      disabled={!@can_manage?}
                      phx-click="delete_environment"
                      phx-value-id={environment.id}
                      phx-confirm={
                        gettext("Delete %{name} and its complete PostgreSQL schema? This cannot be undone.",
                          name: environment.name
                        )
                      }
                    >
                      {gettext("Delete")}
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <div class="environment-grid">
          <section class="environment-panel">
            <h2>{gettext("Create environment")}</h2>
            <p>{gettext("Creates an empty schema and runs all application tenant migrations.")}</p>
            <form id="create-environment-form" phx-submit="create_environment">
              <label>
                <span>{gettext("Name")}</span>
                <input name="environment[name]" required placeholder={gettext("Spring redesign")} />
              </label>
              <label>
                <span>{gettext("Key")}</span>
                <input name="environment[key]" required pattern="[a-z0-9]+(?:-[a-z0-9]+)*" placeholder="spring-redesign" />
              </label>
              <label>
                <span>{gettext("Domain (optional)")}</span>
                <input name="environment[domain]" placeholder="spring.example.com" />
              </label>
              <button type="submit" class="primary" disabled={!@can_manage?} phx-disable-with={gettext("Creating…")}>
                {gettext("Create environment")}
              </button>
            </form>
          </section>

          <section class="environment-panel">
            <h2>{gettext("Copy now")}</h2>
            <p>{gettext("Archives the target, then replaces all of its database content from the source.")}</p>
            <form id="copy-environment-form" phx-submit="queue_copy">
              <.environment_pair_fields environments={@environments} />
              <label>
                <span>{gettext("Note (optional)")}</span>
                <input name="operation[note]" />
              </label>
              <button type="submit" class="primary" disabled={!@can_manage? || length(@environments) < 2}>
                {gettext("Queue copy now")}
              </button>
            </form>
          </section>

          <section class="environment-panel">
            <h2>{gettext("Schedule copy")}</h2>
            <form id="schedule-environment-copy-form" phx-submit="schedule_copy">
              <.environment_pair_fields environments={@environments} />
              <.schedule_fields default_scheduled_at={@default_scheduled_at} />
              <button type="submit" class="primary" disabled={!@can_manage? || length(@environments) < 2}>
                {gettext("Schedule copy")}
              </button>
            </form>
          </section>

          <section class="environment-panel">
            <h2>{gettext("Schedule live switch")}</h2>
            <form id="schedule-live-switch-form" phx-submit="schedule_set_live">
              <label>
                <span>{gettext("Environment")}</span>
                <select name="operation[environment_id]" required>
                  <option :for={environment <- @environments} :if={!environment.live} value={environment.id}>
                    {environment.name}
                  </option>
                </select>
              </label>
              <.schedule_fields default_scheduled_at={@default_scheduled_at} />
              <button type="submit" class="primary" disabled={!@can_manage? || Enum.all?(@environments, & &1.live)}>
                {gettext("Schedule live switch")}
              </button>
            </form>
          </section>
        </div>

        <section class="environment-panel">
          <h2>{gettext("Pending operations")}</h2>
          <p :if={@jobs == []}>{gettext("No copy or live-switch operations are pending.")}</p>
          <div :if={@jobs != []} class="environment-table-wrap">
            <table>
              <thead>
                <tr>
                  <th>{gettext("Operation")}</th>
                  <th>{gettext("Scheduled")}</th>
                  <th>{gettext("State")}</th>
                  <th>{gettext("Actions")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={job <- @jobs} id={"environment-job-#{job.id}"}>
                  <td>{job_description(job, @environments)}</td>
                  <td>{format_scheduled_at(job.scheduled_at)}</td>
                  <td><span class="environment-state">{job.state}</span></td>
                  <td>
                    <button
                      type="button"
                      class="danger small"
                      disabled={!@can_manage?}
                      phx-click="cancel_operation"
                      phx-value-id={job.id}
                      phx-confirm={gettext("Cancel this pending environment operation?")}
                    >
                      {gettext("Cancel")}
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section class="environment-panel">
          <header>
            <div>
              <h2>{gettext("Recovery archives")}</h2>
              <p>{gettext("Archives live in the same database and do not replace external backups.")}</p>
            </div>
            <div class="environment-actions">
              <button
                type="button"
                class="secondary"
                disabled={!@can_manage? || @archives == []}
                phx-click="rollback"
                phx-confirm={gettext("Restore the newest archive as a new non-live environment?")}
              >
                {gettext("Restore newest")}
              </button>
              <button
                type="button"
                class="danger"
                disabled={!@can_manage? || length(@archives) <= 3}
                phx-click="prune_archives"
                phx-value-keep="3"
                phx-confirm={gettext("Permanently drop all but the three newest archives?")}
              >
                {gettext("Prune to three")}
              </button>
            </div>
          </header>
          <p :if={@archives == []}>{gettext("No recovery archives exist for this site.")}</p>
          <ul :if={@archives != []} class="environment-archives">
            <li :for={archive <- @archives}>
              <code>{archive.schema}</code>
              <span>{archive.operation || gettext("Recovered archive")}</span>
            </li>
          </ul>
        </section>
      <% end %>
    </div>
    """
  end

  attr :environments, :list, required: true

  defp environment_pair_fields(assigns) do
    source = Enum.find(assigns.environments, & &1.live) || List.first(assigns.environments)
    target = source && Enum.find(assigns.environments, &(&1.id != source.id))

    assigns =
      assigns
      |> assign(:source_id, source && source.id)
      |> assign(:target_id, target && target.id)

    ~H"""
    <div class="environment-pair">
      <label>
        <span>{gettext("Source")}</span>
        <select name="operation[source_id]" required>
          <option :for={environment <- @environments} value={environment.id} selected={environment.id == @source_id}>
            {environment.name}{if environment.live, do: " • live", else: ""}
          </option>
        </select>
      </label>
      <span class="environment-arrow">→</span>
      <label>
        <span>{gettext("Target")}</span>
        <select name="operation[target_id]" required>
          <option :for={environment <- @environments} value={environment.id} selected={environment.id == @target_id}>
            {environment.name}{if environment.live, do: " • live", else: ""}
          </option>
        </select>
      </label>
    </div>
    """
  end

  attr :default_scheduled_at, :string, required: true

  defp schedule_fields(assigns) do
    ~H"""
    <label>
      <span>{gettext("Run at")}</span>
      <input type="datetime-local" name="operation[scheduled_at]" value={@default_scheduled_at} required />
    </label>
    <label>
      <span>{gettext("Note (optional)")}</span>
      <input name="operation[note]" />
    </label>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("refresh", _params, socket), do: {:noreply, refresh_data(socket)}

  def handle_event("create_environment", %{"environment" => attrs}, socket) do
    with :ok <- authorize(socket),
         {:ok, environment} <-
           Environments.create_environment(socket.assigns.site, attrs, creator: socket.assigns.current_user) do
      {:noreply,
       socket
       |> notify(gettext("Environment %{name} created.", name: environment.name))
       |> refresh_data()}
    else
      {:error, reason} -> {:noreply, notify_error(socket, operation_error(reason))}
    end
  end

  def handle_event("queue_copy", %{"operation" => params}, socket) do
    with :ok <- authorize(socket),
         {:ok, source} <- environment_for_site(socket, params["source_id"]),
         {:ok, target} <- environment_for_site(socket, params["target_id"]),
         {:ok, _job} <-
           Environments.schedule_copy(source, target, DateTime.utc_now(),
             creator: socket.assigns.current_user,
             note: blank_to_nil(params["note"])
           ) do
      {:noreply,
       socket
       |> notify(gettext("Environment copy queued."))
       |> refresh_data()}
    else
      {:error, reason} -> {:noreply, notify_error(socket, operation_error(reason))}
    end
  end

  def handle_event("schedule_copy", %{"operation" => params}, socket) do
    with :ok <- authorize(socket),
         {:ok, source} <- environment_for_site(socket, params["source_id"]),
         {:ok, target} <- environment_for_site(socket, params["target_id"]),
         {:ok, scheduled_at} <- parse_future_datetime(params["scheduled_at"]),
         {:ok, _job} <-
           Environments.schedule_copy(source, target, scheduled_at,
             creator: socket.assigns.current_user,
             note: blank_to_nil(params["note"])
           ) do
      {:noreply,
       socket
       |> notify(gettext("Environment copy scheduled."))
       |> refresh_data()}
    else
      {:error, reason} -> {:noreply, notify_error(socket, operation_error(reason))}
    end
  end

  def handle_event("queue_set_live", %{"id" => id}, socket) do
    with :ok <- authorize(socket),
         {:ok, environment} <- environment_for_site(socket, id),
         {:ok, _job} <-
           Environments.schedule_set_live(environment, DateTime.utc_now(), creator: socket.assigns.current_user) do
      {:noreply,
       socket
       |> notify(gettext("Live switch queued."))
       |> refresh_data()}
    else
      {:error, reason} -> {:noreply, notify_error(socket, operation_error(reason))}
    end
  end

  def handle_event("schedule_set_live", %{"operation" => params}, socket) do
    with :ok <- authorize(socket),
         {:ok, environment} <- environment_for_site(socket, params["environment_id"]),
         {:ok, scheduled_at} <- parse_future_datetime(params["scheduled_at"]),
         {:ok, _job} <-
           Environments.schedule_set_live(environment, scheduled_at,
             creator: socket.assigns.current_user,
             note: blank_to_nil(params["note"])
           ) do
      {:noreply,
       socket
       |> notify(gettext("Live switch scheduled."))
       |> refresh_data()}
    else
      {:error, reason} -> {:noreply, notify_error(socket, operation_error(reason))}
    end
  end

  def handle_event("delete_environment", %{"id" => id}, socket) do
    with :ok <- authorize(socket),
         {:ok, environment} <- environment_for_site(socket, id),
         {:ok, _deleted} <-
           Environments.delete_environment(environment, creator: socket.assigns.current_user) do
      {:noreply,
       socket
       |> notify(gettext("Environment deleted."))
       |> refresh_data()}
    else
      {:error, reason} -> {:noreply, notify_error(socket, operation_error(reason))}
    end
  end

  def handle_event("cancel_operation", %{"id" => id}, socket) do
    with :ok <- authorize(socket),
         {job_id, ""} <- Integer.parse(to_string(id)),
         :ok <- Environments.cancel_scheduled_operation(socket.assigns.site, job_id) do
      {:noreply,
       socket
       |> notify(gettext("Scheduled operation cancelled."))
       |> refresh_data()}
    else
      :error -> {:noreply, notify_error(socket, gettext("Invalid job identifier."))}
      {:error, reason} -> {:noreply, notify_error(socket, operation_error(reason))}
    end
  end

  def handle_event("rollback", _params, socket) do
    with :ok <- authorize(socket),
         {:ok, restored} <-
           Environments.rollback(socket.assigns.site, creator: socket.assigns.current_user) do
      {:noreply,
       socket
       |> notify(gettext("Archive restored as %{name}.", name: restored.name))
       |> refresh_data()}
    else
      {:error, reason} -> {:noreply, notify_error(socket, operation_error(reason))}
    end
  end

  def handle_event("prune_archives", %{"keep" => keep}, socket) do
    with :ok <- authorize(socket),
         {keep, ""} <- Integer.parse(to_string(keep)),
         {:ok, dropped} <- Environments.prune_archives(socket.assigns.site, keep) do
      {:noreply,
       socket
       |> notify(ngettext("Dropped %{count} archive.", "Dropped %{count} archives.", length(dropped)))
       |> refresh_data()}
    else
      :error -> {:noreply, notify_error(socket, gettext("Invalid archive retention count."))}
      {:error, reason} -> {:noreply, notify_error(socket, operation_error(reason))}
    end
  end

  defp refresh_data(socket) do
    site =
      case socket.assigns[:current_site] do
        %{id: site_id} -> Registry.get_site(site_id)
        _ -> nil
      end

    socket
    |> assign(:site, site)
    |> assign(:environments, (site && Registry.list_environments(site)) || [])
    |> assign(:archives, (site && Environments.list_archives(site)) || [])
    |> assign(:jobs, (site && Environments.list_scheduled_operations(site)) || [])
  end

  defp authorize(%{assigns: %{can_manage?: true}}), do: :ok
  defp authorize(_socket), do: {:error, :not_authorized}

  defp environment_for_site(socket, id) do
    with {environment_id, ""} <- Integer.parse(to_string(id)),
         %Environment{} = environment <-
           Enum.find(socket.assigns.environments, &(&1.id == environment_id)) do
      {:ok, environment}
    else
      _ -> {:error, :environment_not_found}
    end
  end

  defp parse_future_datetime(value) when is_binary(value) do
    value = if String.length(value) == 16, do: value <> ":00", else: value

    with {:ok, naive} <- NaiveDateTime.from_iso8601(value),
         {:ok, scheduled_at} <- DateTime.from_naive(naive, Brando.timezone()),
         :gt <- DateTime.compare(scheduled_at, DateTime.utc_now()) do
      {:ok, scheduled_at}
    else
      _ -> {:error, :invalid_scheduled_at}
    end
  end

  defp parse_future_datetime(_value), do: {:error, :invalid_scheduled_at}

  defp default_scheduled_at do
    DateTime.utc_now()
    |> DateTime.add(3_600, :second)
    |> DateTime.shift_zone!(Brando.timezone())
    |> Calendar.strftime("%Y-%m-%dT%H:%M")
  end

  defp format_scheduled_at(scheduled_at) do
    scheduled_at
    |> DateTime.shift_zone!(Brando.timezone())
    |> Calendar.strftime("%Y-%m-%d %H:%M %Z")
  end

  defp job_description(job, environments) do
    cond do
      job.worker == Oban.Worker.to_string(EnvironmentCopy) ->
        source = environment_name(environments, job.args["source_environment_id"])
        target = environment_name(environments, job.args["target_environment_id"])
        gettext("Copy %{source} → %{target}", source: source, target: target)

      job.worker == Oban.Worker.to_string(EnvironmentSetLive) ->
        environment = environment_name(environments, job.args["environment_id"])
        gettext("Set %{environment} live", environment: environment)

      true ->
        job.worker
    end
  end

  defp environment_name(environments, id) do
    case Enum.find(environments, &(to_string(&1.id) == to_string(id))) do
      nil -> gettext("Unknown environment")
      environment -> environment.name
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp blank_to_nil(_value), do: nil

  defp notify(socket, message) do
    send(self(), {:toast, message})
    socket
  end

  defp notify_error(socket, message) do
    BrandoAdmin.Toast.send_to(socket.assigns.current_user, message, %{
      level: :error,
      type: :notification
    })

    socket
  end

  defp operation_error(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, translated ->
        String.replace(translated, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.flat_map(fn {field, messages} -> Enum.map(messages, &"#{field} #{&1}") end)
    |> Enum.join(", ")
  end

  defp operation_error(:not_authorized), do: gettext("You are not allowed to manage environments.")
  defp operation_error(:same_environment), do: gettext("Source and target must be different environments.")
  defp operation_error(:invalid_environment_pair), do: operation_error(:same_environment)
  defp operation_error(:invalid_scheduled_at), do: gettext("Choose a valid future date and time.")
  defp operation_error(:live_environment), do: gettext("The live environment cannot be deleted.")
  defp operation_error(:environment_not_found), do: gettext("The environment no longer exists.")
  defp operation_error(:job_not_found), do: gettext("The scheduled operation no longer exists.")
  defp operation_error(:no_archives), do: gettext("No recovery archive exists for this site.")
  defp operation_error(reason), do: gettext("Environment operation failed: %{reason}", reason: inspect(reason))
end
