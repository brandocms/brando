defmodule BrandoAdmin.Sites.PublishingLive do
  @moduledoc false

  use BrandoAdmin, :live_view
  use BrandoAdmin.Toast
  use Gettext, backend: Brando.Gettext

  alias Brando.Environments.Environment
  alias Brando.SSG.Build
  alias Brando.SSG.Builds
  alias Brando.Tenant
  alias Brando.Tenant.Access
  alias Brando.Tenant.Registry
  alias Brando.Worker.SSGDeploy
  alias BrandoAdmin.Components.Content

  @manager_roles [:admin, :superuser]

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    site = socket.assigns[:current_site]

    cond do
      is_nil(site) or site.delivery_mode != :static ->
        {:ok, redirect(socket, to: "/admin")}

      connected?(socket) ->
        Phoenix.PubSub.subscribe(Brando.pubsub(), Builds.topic(site))

        {:ok,
         socket
         |> assign(:socket_connected, true)
         |> assign(:site, site)
         |> assign(:can_manage?, can_manage?(socket.assigns.current_user, site))
         |> assign(:default_scheduled_at, default_scheduled_at())
         |> refresh()}

      true ->
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
      title={gettext("Publishing")}
      subtitle={gettext("Build, preview, deploy, and roll back versioned static artifacts")}
    >
      <button type="button" class="secondary" phx-click="refresh">{gettext("Refresh")}</button>
    </Content.header>

    <div class="environment-management-live">
      <div :if={!@can_manage?} class="environment-notice warning">
        {gettext("Only site administrators and superusers can publish static builds.")}
      </div>

      <section class="environment-panel environment-overview">
        <header>
          <div>
            <h2>{@site.name}</h2>
            <p>{deploy_summary(@site.deploy_config)}</p>
          </div>
          <span class="environment-state live">{gettext("Static delivery")}</span>
        </header>

        <form id="build-static-site" phx-submit="request_build">
          <label>
            <span>{gettext("Content environment")}</span>
            <select name="build[environment_id]" required>
              <option :for={environment <- @environments} value={environment.id}>
                {environment.name}{if environment.live, do: " • live", else: ""}
              </option>
            </select>
          </label>
          <label>
            <span>{gettext("Note (optional)")}</span>
            <input name="build[note]" placeholder={gettext("Homepage campaign update")} />
          </label>
          <label>
            <input type="checkbox" name="build[auto_deploy]" value="true" checked={auto_deploy?(@site)} />
            <span>{gettext("Deploy automatically after a successful build")}</span>
          </label>
          <div class="environment-actions">
            <button
              type="submit"
              class="primary"
              disabled={!@can_manage?}
              phx-disable-with={gettext("Queueing…")}
            >
              {gettext("Build now")}
            </button>
          </div>
        </form>

        <form id="schedule-static-site" phx-submit="schedule_build">
          <label>
            <span>{gettext("Schedule a build")}</span>
            <input type="datetime-local" name="build[scheduled_at]" value={@default_scheduled_at} required />
          </label>
          <label>
            <span>{gettext("Content environment")}</span>
            <select name="build[environment_id]" required>
              <option :for={environment <- @environments} value={environment.id}>
                {environment.name}{if environment.live, do: " • live", else: ""}
              </option>
            </select>
          </label>
          <label>
            <input type="checkbox" name="build[auto_deploy]" value="true" checked={auto_deploy?(@site)} />
            <span>{gettext("Deploy automatically")}</span>
          </label>
          <button type="submit" class="secondary" disabled={!@can_manage?}>
            {gettext("Schedule")}
          </button>
        </form>
      </section>

      <section class="environment-panel">
        <h2>{gettext("Deployment target")}</h2>
        <p>
          {gettext(
            "This publishes static artifacts only. Florist continues to deploy and roll back the Phoenix application release."
          )}
        </p>
        <form id="static-deploy-config" phx-submit="save_deploy_config">
          <label>
            <span>{gettext("Strategy")}</span>
            <select name="deploy[strategy]">
              <option value="">{gettext("Build and preview only")}</option>
              <option value="rsync" selected={deploy_value(@site, :strategy) == :rsync}>Rsync</option>
              <option value="s3" selected={deploy_value(@site, :strategy) == :s3}>Amazon S3</option>
            </select>
          </label>
          <label>
            <span>{gettext("Target")}</span>
            <input
              name="deploy[target]"
              value={deploy_value(@site, :target)}
              placeholder="deploy@example.com:/srv/www or s3://bucket/prefix"
            />
          </label>
          <label>
            <span>{gettext("Public CDN URL (optional)")}</span>
            <input name="deploy[cdn_url]" value={deploy_value(@site, :cdn_url)} placeholder="https://www.example.com" />
          </label>
          <label>
            <span>{gettext("Completion webhook (optional)")}</span>
            <input
              name="deploy[webhook_url]"
              value={deploy_value(@site, :webhook_url)}
              placeholder="https://hooks.example.com/static-published"
            />
          </label>
          <label>
            <span>{gettext("Artifact retention")}</span>
            <input
              type="number"
              min="1"
              max="100"
              name="deploy[retention_count]"
              value={deploy_value(@site, :retention_count) || 10}
            />
          </label>
          <label>
            <input
              type="checkbox"
              name="deploy[auto_deploy]"
              value="true"
              checked={auto_deploy?(@site)}
            />
            <span>{gettext("Default new builds to automatic deployment")}</span>
          </label>
          <button type="submit" class="secondary" disabled={!@can_manage?}>
            {gettext("Save deployment settings")}
          </button>
        </form>
      </section>

      <section class="environment-panel">
        <header>
          <div>
            <h2>{gettext("Build history")}</h2>
            <p>{gettext("Artifacts are stored outside the OTP release and survive blue/green switches.")}</p>
          </div>
          <span class="environment-count">
            {ngettext("%{count} build", "%{count} builds", length(@builds))}
          </span>
        </header>

        <div :if={@builds == []} class="environment-notice">
          {gettext("No static builds have been requested yet.")}
        </div>

        <div :if={@builds != []} class="environment-table-wrap">
          <table>
            <thead>
              <tr>
                <th>{gettext("Version")}</th>
                <th>{gettext("Environment")}</th>
                <th>{gettext("Progress")}</th>
                <th>{gettext("State")}</th>
                <th>{gettext("Created")}</th>
                <th>{gettext("Actions")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={build <- @builds} id={"ssg-build-#{build.id}"}>
                <td>
                  <strong>{build.version}</strong>
                  <code>{build.note || asset_name(build)}</code>
                </td>
                <td>{build.environment_name}</td>
                <td>{build.processed_urls}/{build.url_count}</td>
                <td>
                  <span class={["environment-state", build.status == :deployed && "live"]}>
                    {human_status(build.status)}
                  </span>
                  <small :if={build.pruned_at}>{gettext("artifact pruned")}</small>
                </td>
                <td>{format_datetime(build.scheduled_at || build.inserted_at)}</td>
                <td class="environment-actions">
                  <a
                    :if={previewable?(build)}
                    class="button secondary small"
                    href={preview_url(build)}
                    target="_blank"
                    rel="noreferrer"
                  >
                    {gettext("Preview")}
                  </a>
                  <a
                    :if={build.status == :deployed && public_url(build)}
                    class="button secondary small"
                    href={public_url(build)}
                    target="_blank"
                    rel="noreferrer"
                  >
                    {gettext("Open site")}
                  </a>
                  <button
                    :if={build.status == :ready && is_nil(build.pruned_at)}
                    type="button"
                    class="primary small"
                    disabled={!@can_manage? || !deploy_configured?(@site)}
                    phx-click="deploy"
                    phx-value-id={build.id}
                    phx-confirm={gettext("Deploy %{version}?", version: build.version)}
                  >
                    {gettext("Deploy")}
                  </button>
                  <button
                    :if={build.status == :archived && is_nil(build.pruned_at)}
                    type="button"
                    class="secondary small"
                    disabled={!@can_manage? || !deploy_configured?(@site)}
                    phx-click="rollback"
                    phx-value-id={build.id}
                    phx-confirm={gettext("Roll back to %{version}?", version: build.version)}
                  >
                    {gettext("Roll back")}
                  </button>
                  <details :if={build.build_log != "" || build.failed_urls != []}>
                    <summary>{gettext("Log")}</summary>
                    <pre>{build.build_log}</pre>
                    <ul :if={build.failed_urls != []}>
                      <li :for={failed_url <- build.failed_urls}>{failed_url}</li>
                    </ul>
                  </details>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("refresh", _params, socket), do: {:noreply, refresh(socket)}

  def handle_event("request_build", %{"build" => params}, socket) do
    queue_build(socket, params, nil)
  end

  def handle_event("schedule_build", %{"build" => params}, socket) do
    case parse_future_datetime(params["scheduled_at"]) do
      {:ok, scheduled_at} -> queue_build(socket, params, scheduled_at)
      {:error, _reason} -> toast_error(socket, gettext("Choose a valid future date and time."))
    end
  end

  def handle_event("save_deploy_config", %{"deploy" => params}, socket) do
    attrs = %{
      strategy: deploy_strategy(params["strategy"]),
      target: blank_to_nil(params["target"]),
      cdn_url: blank_to_nil(params["cdn_url"]),
      webhook_url: blank_to_nil(params["webhook_url"]),
      auto_deploy: params["auto_deploy"] == "true",
      retention_count: parse_integer(params["retention_count"], 10)
    }

    with true <- socket.assigns.can_manage?,
         {:ok, _site} <- Registry.update_site(socket.assigns.site, %{deploy_config: attrs}) do
      send(self(), {:toast, gettext("Static deployment settings saved")})
      {:noreply, refresh(socket)}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        toast_error(socket, BrandoAdmin.Utils.format_changeset_errors(changeset))

      _error ->
        toast_error(socket, gettext("Could not save static deployment settings."))
    end
  end

  def handle_event(action, %{"id" => id}, socket) when action in ["deploy", "rollback"] do
    with true <- socket.assigns.can_manage?,
         {build_id, ""} <- Integer.parse(id),
         %Build{site_id: site_id} <- Enum.find(socket.assigns.builds, &(&1.id == build_id)),
         true <- site_id == socket.assigns.site.id,
         {:ok, _job} <-
           %{"build_id" => build_id, "action" => action}
           |> SSGDeploy.new(tags: ["ssg-deploy", "site:#{site_id}"])
           |> Oban.insert() do
      send(self(), {:toast, gettext("Static %{action} queued", action: action)})
      {:noreply, socket}
    else
      _error -> toast_error(socket, gettext("Could not queue the publishing action."))
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:ssg_build_updated, _build}, socket), do: {:noreply, refresh(socket)}

  defp queue_build(socket, params, scheduled_at) do
    with true <- socket.assigns.can_manage?,
         %Environment{} = environment <- environment(socket, params["environment_id"]),
         {:ok, build} <-
           Builds.request_build(socket.assigns.site, environment,
             creator_id: socket.assigns.current_user.id,
             note: blank_to_nil(params["note"]),
             auto_deploy: params["auto_deploy"] == "true",
             scheduled_at: scheduled_at
           ) do
      send(self(), {:toast, gettext("Queued static build %{version}", version: build.version)})
      {:noreply, refresh(socket)}
    else
      _error -> toast_error(socket, gettext("Could not queue the static build."))
    end
  end

  defp environment(socket, id) when is_binary(id) do
    case Integer.parse(id) do
      {environment_id, ""} -> Enum.find(socket.assigns.environments, &(&1.id == environment_id))
      _invalid -> nil
    end
  end

  defp environment(_socket, _id), do: nil

  defp refresh(socket) do
    site = Registry.get_site(socket.assigns.site.id)

    socket
    |> assign(:site, site)
    |> assign(:environments, site.environments |> Enum.sort_by(&{not &1.live, &1.name}))
    |> assign(:builds, Builds.list_builds(site))
  end

  defp can_manage?(user, site) do
    case Tenant.mode() do
      :multi -> Access.can_manage?(user, site)
      _other -> user.role in @manager_roles
    end
  end

  defp parse_future_datetime(value) when is_binary(value) do
    with {:ok, naive} <- NaiveDateTime.from_iso8601(value <> ":00"),
         {:ok, scheduled_at} <- DateTime.from_naive(naive, Brando.timezone()),
         :gt <- DateTime.compare(scheduled_at, DateTime.utc_now()) do
      {:ok, scheduled_at}
    else
      _invalid -> {:error, :invalid_scheduled_at}
    end
  end

  defp parse_future_datetime(_value), do: {:error, :invalid_scheduled_at}

  defp default_scheduled_at do
    Brando.timezone()
    |> DateTime.now!()
    |> DateTime.add(10, :minute)
    |> Calendar.strftime("%Y-%m-%dT%H:%M")
  end

  defp toast_error(socket, message) do
    BrandoAdmin.Toast.send_to(socket.assigns.current_user, message, %{
      level: :error,
      type: :notification
    })

    {:noreply, socket}
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp deploy_strategy("rsync"), do: :rsync
  defp deploy_strategy("s3"), do: :s3
  defp deploy_strategy(_none), do: nil

  defp parse_integer(value, default) do
    case Integer.parse(to_string(value)) do
      {integer, ""} -> integer
      _invalid -> default
    end
  end

  defp auto_deploy?(site), do: site.deploy_config && site.deploy_config.auto_deploy

  defp deploy_value(%{deploy_config: nil}, _field), do: nil
  defp deploy_value(%{deploy_config: config}, field), do: Map.get(config, field)

  defp deploy_configured?(site) do
    site.deploy_config && site.deploy_config.strategy && site.deploy_config.target not in [nil, ""]
  end

  defp deploy_summary(nil), do: gettext("No deployment target configured; builds and previews remain available.")

  defp deploy_summary(config) do
    if config.strategy && config.target not in [nil, ""] do
      gettext("Deploy via %{strategy} to %{target}", strategy: config.strategy, target: config.target)
    else
      gettext("No deployment target configured; builds and previews remain available.")
    end
  end

  defp asset_name(%Build{asset_set: nil}), do: gettext("release assets")
  defp asset_name(%Build{asset_set: asset_set}), do: asset_set.name

  defp previewable?(build),
    do: build.status in [:ready, :deployed, :archived] and is_nil(build.pruned_at)

  defp preview_url(build), do: "/__ssg_preview__/#{build.preview_token}/"

  defp public_url(build), do: build.deploy_config["cdn_url"]

  defp human_status(status), do: status |> Atom.to_string() |> String.capitalize()

  defp format_datetime(nil), do: "—"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")
end
