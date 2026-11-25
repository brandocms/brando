defmodule BrandoAdmin.Sites.PublishingLive do
  @moduledoc false

  use BrandoAdmin, :live_view
  use BrandoAdmin.Toast
  use Gettext, backend: Brando.Gettext

  # Changing where a site deploys to (its target and webhook, its SSH key and
  # accepted host keys), building (which may deploy at once), deploying and
  # rolling back ask for the password, a code or a passkey when the session
  # has not confirmed lately.
  on_mount(
    {BrandoAdmin.Reauth,
     events: ~w(save_deploy_config rotate_deploy_key accept_host_keys deploy rollback request_build schedule_build)}
  )

  # Builds, deploys and rollbacks report on their rows
  on_mount BrandoAdmin.Work

  alias Brando.Environments.Environment
  alias Brando.Sites.DeployConfig
  alias Brando.Sites.Site
  alias Brando.SSG.Build
  alias Brando.SSG.Builds
  alias Brando.SSG.DeployFiles
  alias Brando.SSG.SSH
  alias Brando.Tenant.Registry
  alias Brando.Worker.SSGBuild
  alias Brando.Worker.SSGDeploy
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Work, as: WorkComponent
  alias BrandoAdmin.Work

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
         |> assign(:admin_uri, socket.host_uri)
         |> assign(:can_manage?, can_manage?(socket.assigns.current_user, site))
         |> assign(:default_scheduled_at, default_scheduled_at())
         |> assign(:connection_test, nil)
         |> refresh()
         |> assign_strategy()}

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
    <div class="environment-screen">
      <Content.header
        title={gettext("Publishing")}
        subtitle={gettext("Build, preview, deploy, and roll back versioned static artifacts")}
      >
        <button type="button" class="btn" phx-click="refresh">{gettext("Refresh")}</button>
      </Content.header>

      <div class="environment-management-live">
        <div :if={!@can_manage?} class="environment-notice warning">
          {gettext("Only site administrators and superusers can publish static builds.")}
        </div>

        <section class="environment-panel environment-overview publishing-overview">
          <header>
            <div>
              <h2>{@site.name}</h2>
              <p>{deploy_summary(@site)}</p>
            </div>
            <span class="badge badge--success"><span class="badge-dot"></span>{gettext("Static delivery")}</span>
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
            <label :if={deploy_configured?(@site)} class="environment-check">
              <input
                type="checkbox"
                name="build[auto_deploy]"
                value="true"
                checked={auto_deploy?(@site) && BrandoAdmin.Authorization.allowed?(:deploy, :publishing)}
                disabled={!BrandoAdmin.Authorization.allowed?(:deploy, :publishing)}
              />
              <span>{gettext("Deploy automatically after a successful build")}</span>
            </label>
            <div class="environment-actions">
              <button
                type="submit"
                class="btn btn--primary"
                disabled={!@can_manage? || !BrandoAdmin.Authorization.allowed?(:build, :publishing)}
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
            <label :if={deploy_configured?(@site)} class="environment-check">
              <input
                type="checkbox"
                name="build[auto_deploy]"
                value="true"
                checked={auto_deploy?(@site) && BrandoAdmin.Authorization.allowed?(:deploy, :publishing)}
                disabled={!BrandoAdmin.Authorization.allowed?(:deploy, :publishing)}
              />
              <span>{gettext("Deploy automatically")}</span>
            </label>
            <button
              type="submit"
              class="btn"
              disabled={
                !@can_manage? || !BrandoAdmin.Authorization.allowed?(:build, :publishing) ||
                  !BrandoAdmin.Authorization.allowed?(:schedule, :publishing)
              }
            >
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
          <form id="static-deploy-config" phx-change="change_deploy_config" phx-submit="save_deploy_config">
            <label>
              <span>{gettext("Strategy")}</span>
              <select name="deploy[strategy]">
                <option value="">{gettext("Build and preview only")}</option>
                <option :if={local_delivery_offered?(@site)} value="local" selected={@strategy == "local"}>
                  {gettext("Served by this installation")}
                </option>
                <option value="rsync" selected={@strategy == "rsync"}>Rsync</option>
                <option value="s3" selected={@strategy == "s3"}>Amazon S3</option>
              </select>
            </label>
            <div :if={@strategy == "local"} class="alert environment-hint">
              <.icon name="info" />
              <span>{local_delivery_note(@site)}</span>
            </div>
            <div :if={@strategy != "local"} class="publishing-target">
              <label>
                <span>{gettext("Target")}</span>
                <input
                  name="deploy[target]"
                  value={deploy_value(@site, :target)}
                  placeholder="deploy@example.com:/srv/www or s3://bucket/prefix"
                />
              </label>
              <label :if={@strategy == "rsync"} class="publishing-port">
                <span>{gettext("SSH port")}</span>
                <input type="number" min="1" max="65535" name="deploy[port]" value={deploy_value(@site, :port) || 22} />
              </label>
            </div>
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
            <label :if={deploy_configured?(@site)} class="environment-check">
              <input
                type="checkbox"
                name="deploy[auto_deploy]"
                value="true"
                checked={auto_deploy?(@site)}
              />
              <span>{gettext("Default new builds to automatic deployment")}</span>
            </label>
            <button
              type="submit"
              class="btn"
              disabled={!@can_manage? || !BrandoAdmin.Authorization.allowed?(:deploy, :publishing)}
            >
              {gettext("Save deployment settings")}
            </button>
          </form>
        </section>

        <.ssh_access
          :if={@can_manage? && rsync_saved?(@site)}
          public_key={@public_key}
          key_problem={@key_problem}
          connection_test={@connection_test}
          can_deploy?={BrandoAdmin.Authorization.allowed?(:deploy, :publishing)}
        />

        <section class="environment-panel publishing-builds">
          <header>
            <div>
              <h2>{gettext("Build history")}</h2>
              <p>{gettext("Artifacts are stored outside the OTP release and survive blue/green switches.")}</p>
            </div>
            <span class="badge">
              {ngettext("%{count} build", "%{count} builds", length(@builds))}
            </span>
          </header>

          <div :if={@builds == []} class="environment-notice">
            {gettext("No static builds have been requested yet.")}
          </div>

          <div :if={@builds != []} class="environment-table-wrap environment-stacking">
            <table>
              <thead>
                <tr>
                  <th>{gettext("Version")}</th>
                  <th>{gettext("Environment")}</th>
                  <th>{gettext("Progress")}</th>
                  <th>{gettext("State")}</th>
                  <th>{gettext("Created")}</th>
                  <th class="environment-actions">{gettext("Actions")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={build <- @builds} id={"ssg-build-#{build.id}"}>
                  <td>
                    <strong>{build.version}</strong>
                    <code>{build.note || asset_name(build)}</code>
                  </td>
                  <td>{build.environment_name}</td>
                  <td class="publishing-progress">
                    <span class="publishing-progress__label">{gettext("Progress")}</span>
                    <span :if={!failed_urls?(build)}>{build.processed_urls}/{build.url_count}</span>
                    <span :if={failed_urls?(build)}>
                      {gettext("%{built}/%{total} built", built: build.processed_urls, total: build.url_count)}
                    </span>
                    <span :if={failed_urls?(build)} class="publishing-progress__failed">
                      {gettext("%{count} failed", count: length(build.failed_urls))}
                    </span>
                  </td>
                  <td>
                    <span class={["badge", build_tone(build.status)]}>
                      <span :if={build.status == :deployed} class="badge-dot"></span>
                      {human_status(build.status)}
                    </span>
                    <small :if={published?(build, @site)} class="publishing-served">{gettext("served by this installation")}</small>
                    <small :if={build.pruned_at}>{gettext("artifact pruned")}</small>
                    <WorkComponent.status
                      key={SSGBuild.work_key(build.id)}
                      work={@work[SSGBuild.work_key(build.id)]}
                      global
                      class="publishing-build-work"
                    />
                  </td>
                  <td>{format_datetime(build.scheduled_at || build.inserted_at)}</td>
                  <td class="environment-actions">
                    <a
                      :if={previewable?(build) && preview_url(build, @site, @admin_uri)}
                      class="btn btn--sm"
                      href={preview_url(build, @site, @admin_uri)}
                      target="_blank"
                      rel="noreferrer"
                    >
                      {gettext("Preview")}
                    </a>
                    <a
                      :if={build.status == :deployed && public_url(build, @site, @admin_uri)}
                      class="btn btn--sm"
                      href={public_url(build, @site, @admin_uri)}
                      target="_blank"
                      rel="noreferrer"
                    >
                      {gettext("Open site")}
                    </a>
                    <button
                      :if={build.status == :ready && is_nil(build.pruned_at)}
                      type="button"
                      class="btn btn--sm btn--primary"
                      disabled={
                        !@can_manage? || !BrandoAdmin.Authorization.allowed?(:deploy, :publishing) ||
                          !deploy_configured?(@site)
                      }
                      phx-click="deploy"
                      phx-value-id={build.id}
                      data-confirm={gettext("Deploy %{version}?", version: build.version)}
                      data-confirm-ok={gettext("Deploy")}
                    >
                      {gettext("Deploy")}
                    </button>
                    <button
                      :if={build.status == :archived && is_nil(build.pruned_at)}
                      type="button"
                      class="btn btn--sm"
                      disabled={
                        !@can_manage? || !BrandoAdmin.Authorization.allowed?(:deploy, :publishing) ||
                          !deploy_configured?(@site)
                      }
                      phx-click="rollback"
                      phx-value-id={build.id}
                      data-confirm={gettext("Roll back to %{version}?", version: build.version)}
                      data-confirm-ok={gettext("Roll back")}
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
    </div>
    """
  end

  attr :public_key, :string
  attr :key_problem, :atom
  attr :connection_test, :any
  attr :can_deploy?, :boolean

  # The site's own key and the host keys it accepted (Brando.SSG.SSH)
  defp ssh_access(assigns) do
    ~H"""
    <section class="environment-panel publishing-ssh" id="publishing-ssh">
      <h2>{gettext("SSH access")}</h2>
      <p>
        {gettext(
          "Deploys connect with this site's own key, and only to a host whose key you accepted here. Add the public key to the authorized_keys file of the target's user on the host, then test the connection."
        )}
      </p>

      <div :if={@key_problem} class="alert environment-hint" role="alert">
        <.icon name="triangle-alert" />
        <span>{key_problem_message(@key_problem)}</span>
      </div>

      <div :if={@public_key} id="publishing-public-key" class="publishing-public-key" phx-hook="Brando.CopyText">
        <label>
          <span>{gettext("Public key")}</span>
          <input type="text" readonly value={@public_key} spellcheck="false" autocomplete="off" data-copy-source />
        </label>
        <button type="button" class="btn" data-copy-button data-copied={gettext("Copied")}>
          {gettext("Copy")}
        </button>
      </div>

      <div class="environment-actions publishing-ssh-actions">
        <button
          :if={@public_key}
          type="button"
          class="btn"
          phx-click="test_connection"
          disabled={!@can_deploy? || @connection_test == :running}
        >
          {if @connection_test == :running, do: gettext("Testing…"), else: gettext("Test connection")}
        </button>
        <button
          :if={@public_key || @key_problem == :unreadable_key}
          type="button"
          class="btn"
          disabled={!@can_deploy?}
          phx-click="rotate_deploy_key"
          data-confirm={
            gettext(
              "Replace the site's key with a new one? Deploys use the new key at once, so add it to the host first. The old key stays authorized on the host until you remove it from authorized_keys there."
            )
          }
          data-confirm-ok={gettext("Rotate key")}
        >
          {gettext("Rotate key")}
        </button>
        <button
          :if={is_nil(@public_key) && is_nil(@key_problem)}
          type="button"
          class="btn btn--primary"
          disabled={!@can_deploy?}
          phx-click="rotate_deploy_key"
        >
          {gettext("Make key")}
        </button>
      </div>

      <.connection_result :if={is_tuple(@connection_test)} result={@connection_test} can_deploy?={@can_deploy?} />
    </section>
    """
  end

  attr :result, :any
  attr :can_deploy?, :boolean

  defp connection_result(%{result: {:error, reason}} = assigns) do
    assigns = assign(assigns, :message, connection_error(reason))

    ~H"""
    <div class="alert environment-hint publishing-ssh-result" role="status" data-testid="connection-result">
      <.icon name="triangle-alert" />
      <span>{@message}</span>
    </div>
    """
  end

  defp connection_result(%{result: {:ok, test}} = assigns) do
    assigns = assign(assigns, :test, test)

    ~H"""
    <div class="publishing-ssh-result" data-testid="connection-result" data-state={@test.host_key_state}>
      <div :if={@test.host_key_state == :new} class="alert environment-hint" role="status">
        <.icon name="info" />
        <span>
          {gettext(
            "No host key is accepted for %{host}. Compare these fingerprints with the host's own before you accept them.",
            host: host_label(@test)
          )}
        </span>
      </div>
      <div :if={@test.host_key_state == :changed} class="alert environment-hint" role="alert">
        <.icon name="triangle-alert" />
        <span>
          {gettext(
            "The host's keys are not the ones accepted for %{host}. Accept them only if you know why the host changed, such as a rebuilt server.",
            host: host_label(@test)
          )}
        </span>
      </div>

      <dl class="publishing-fingerprints">
        <div>
          <dt>{gettext("Host keys")}</dt>
          <dd :for={key <- @test.host_keys}><code>{key.type} {key.fingerprint}</code></dd>
        </div>
        <div :if={@test.host_key_state == :changed}>
          <dt>{gettext("Accepted keys")}</dt>
          <dd :for={key <- @test.accepted_keys}><code>{key.type} {key.fingerprint}</code></dd>
        </div>
      </dl>

      <div :if={@test.host_key_state != :accepted} class="environment-actions">
        <button
          type="button"
          class="btn btn--primary"
          disabled={!@can_deploy?}
          phx-click="accept_host_keys"
          data-confirm={gettext("Accept these host keys for %{host}?", host: host_label(@test))}
          data-confirm-ok={gettext("Accept host key")}
        >
          {gettext("Accept host key")}
        </button>
      </div>

      <div :if={@test.dry_run == :ok} class="alert environment-hint" role="status">
        <.icon name="circle-check" />
        <span>{gettext("Connected: ssh, the site's key and rsync on the host work.")}</span>
      </div>
      <div :if={match?({:error, _}, @test.dry_run)} class="alert environment-hint" role="alert">
        <.icon name="triangle-alert" />
        <span>{connection_error(elem(@test.dry_run, 1))}</span>
      </div>
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

  # The target field shows for the strategy chosen, before it is saved
  def handle_event("change_deploy_config", %{"deploy" => params}, socket),
    do: {:noreply, assign(socket, :strategy, params["strategy"] || "")}

  def handle_event("save_deploy_config", %{"deploy" => params}, socket) do
    attrs = %{
      strategy: deploy_strategy(params["strategy"]),
      target: blank_to_nil(params["target"]),
      port: parse_integer(params["port"], 22),
      cdn_url: blank_to_nil(params["cdn_url"]),
      webhook_url: blank_to_nil(params["webhook_url"]),
      auto_deploy: params["auto_deploy"] == "true",
      retention_count: parse_integer(params["retention_count"], 10)
    }

    user = socket.assigns.current_user

    with true <- can_manage?(user, socket.assigns.site),
         {:ok, site} <- Registry.update_site(socket.assigns.site, %{deploy_config: attrs}) do
      # The key is made with the first rsync settings; where it cannot be
      # kept, the panel says why
      if rsync_saved?(site), do: SSH.ensure_key(site, user)
      send(self(), {:toast, gettext("Static deployment settings saved")})
      {:noreply, socket |> assign(:connection_test, nil) |> refresh() |> assign_strategy()}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        toast_error(socket, BrandoAdmin.Utils.format_changeset_errors(changeset))

      _error ->
        toast_error(socket, gettext("Could not save static deployment settings."))
    end
  end

  def handle_event("rotate_deploy_key", _params, socket) do
    case SSH.rotate_key(socket.assigns.site, socket.assigns.current_user) do
      {:ok, _public_key} ->
        send(self(), {:toast, gettext("The site has a new SSH key")})
        {:noreply, socket |> assign(:connection_test, nil) |> refresh()}

      {:error, reason} ->
        toast_error(socket, connection_error(reason))
    end
  end

  # Runs beside the screen: the host may take its time to answer
  def handle_event("test_connection", _params, %{assigns: %{connection_test: :running}} = socket),
    do: {:noreply, socket}

  def handle_event("test_connection", _params, socket) do
    site = socket.assigns.site
    user = socket.assigns.current_user

    {:noreply,
     socket
     |> assign(:connection_test, :running)
     |> start_async(:connection_test, fn -> SSH.test_connection(site, user) end)}
  end

  # What is accepted is what the test showed, not a second fetch
  def handle_event("accept_host_keys", _params, %{assigns: %{connection_test: {:ok, test}}} = socket) do
    case SSH.accept_host_keys(socket.assigns.site, socket.assigns.current_user, test) do
      :ok ->
        send(self(), {:toast, gettext("Host key accepted")})
        handle_event("test_connection", %{}, socket)

      {:error, reason} ->
        toast_error(socket, connection_error(reason))
    end
  end

  def handle_event("accept_host_keys", _params, socket),
    do: toast_error(socket, gettext("Test the connection first."))

  # The job reports on the build's row, or as a toast elsewhere (BrandoAdmin.Work)
  def handle_event(action, %{"id" => id}, socket) when action in ["deploy", "rollback"] do
    user = socket.assigns.current_user

    with true <- can_manage?(socket.assigns.current_user, socket.assigns.site),
         {build_id, ""} <- Integer.parse(id),
         %Build{site_id: site_id} = build <- Enum.find(socket.assigns.builds, &(&1.id == build_id)),
         true <- site_id == socket.assigns.site.id,
         {:ok, _job} <-
           %{"build_id" => build_id, "action" => action, "creator_id" => user.id}
           |> SSGDeploy.new(tags: ["ssg-deploy", "site:#{site_id}"])
           # It waits behind any build on the one-at-a-time queue
           |> Work.track(
             user,
             SSGBuild.work_key(build_id),
             [global: true, timeout: to_timeout(hour: 1)] ++ deploy_messages(action, build.version)
           )
           |> Oban.insert() do
      {:noreply, socket}
    else
      _error -> toast_error(socket, gettext("Could not queue the publishing action."))
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:ssg_build_updated, _build}, socket), do: {:noreply, refresh(socket)}

  @impl Phoenix.LiveView
  def handle_async(:connection_test, {:ok, result}, socket), do: {:noreply, assign(socket, :connection_test, result)}

  def handle_async(:connection_test, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, :connection_test, {:error, :test_failed})}

  defp deploy_messages("deploy", version) do
    [
      queued: gettext("Deploy of %{version} is queued", version: version),
      running: gettext("Deploying %{version}", version: version),
      done: gettext("%{version} is deployed", version: version),
      failed: gettext("Could not deploy %{version}", version: version)
    ]
  end

  defp deploy_messages("rollback", version) do
    [
      queued: gettext("Rollback to %{version} is queued", version: version),
      running: gettext("Rolling back to %{version}", version: version),
      done: gettext("Rolled back to %{version}", version: version),
      failed: gettext("Could not roll back to %{version}", version: version)
    ]
  end

  defp queue_build(socket, params, scheduled_at) do
    with true <- can_manage?(socket.assigns.current_user, socket.assigns.site),
         %Environment{} = environment <- environment(socket, params["environment_id"]),
         {:ok, build} <-
           Builds.request_build(socket.assigns.site, environment,
             creator_id: socket.assigns.current_user.id,
             note: blank_to_nil(params["note"]),
             auto_deploy: params["auto_deploy"] == "true",
             scheduled_at: scheduled_at
           ) do
      # An immediate build reports on its row (BrandoAdmin.Work); a scheduled one waits
      if scheduled_at, do: send(self(), {:toast, gettext("Scheduled static build %{version}", version: build.version)})
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
    |> assign_key(site)
  end

  # The public key, for those who may change it; the private key stays in its file
  defp assign_key(socket, site) do
    {public_key, problem} =
      cond do
        not (socket.assigns.can_manage? and rsync_saved?(site)) -> {nil, nil}
        match?({:error, _}, DeployFiles.check_location(site)) -> {nil, elem(DeployFiles.check_location(site), 1)}
        true -> site |> SSH.public_key() |> key_or_problem()
      end

    assign(socket, public_key: public_key, key_problem: problem)
  end

  defp key_or_problem({:ok, public_key}), do: {public_key, nil}
  defp key_or_problem({:error, :no_key}), do: {nil, nil}
  defp key_or_problem({:error, :unreadable_key}), do: {nil, :unreadable_key}

  defp rsync_saved?(%{deploy_config: %{strategy: :rsync, target: target}}) when target not in [nil, ""], do: true
  defp rsync_saved?(_site), do: false

  defp host_label(%{target: target, port: 22}), do: DeployConfig.rsync_host(target)
  defp host_label(%{target: target, port: port}), do: "#{DeployConfig.rsync_host(target)}, port #{port}"

  defp key_problem_message(:served),
    do:
      gettext(
        "Brando keeps no SSH key for this site: its deploy directory is inside a directory the installation serves (media or static files). Set :sites_path in the config outside them."
      )

  defp key_problem_message(:unsafe_path),
    do:
      gettext(
        "Brando keeps no SSH key for this site: the path of its deploy directory has characters ssh reads specially. Set :sites_path in the config to a path of letters, digits and . _ + @ - /."
      )

  defp key_problem_message(:unreadable_key),
    do: gettext("The site's SSH key could not be read. Rotate it to make a new one.")

  # What ssh, rsync or the host said is escaped and cut (`Brando.SSG.SSH.remote_output/1`)
  defp connection_error(:forbidden), do: gettext("You may not change this site's deployment settings.")
  defp connection_error(:not_rsync), do: gettext("Save rsync deployment settings first.")
  defp connection_error(:no_key), do: gettext("The site has no SSH key yet.")
  defp connection_error(:unreadable_key), do: key_problem_message(:unreadable_key)
  defp connection_error(:deploy_files_served), do: key_problem_message(:served)
  defp connection_error(:deploy_files_unsafe_path), do: key_problem_message(:unsafe_path)
  defp connection_error({:error, reason}), do: connection_error(reason)
  defp connection_error(:invalid_deploy_target), do: gettext("The target is not one this site may deploy to.")

  defp connection_error(:deploy_target_lookup_failed),
    do: gettext("The target's host could not be looked up. Try again in a moment.")

  defp connection_error(:target_changed),
    do: gettext("The deployment settings changed after the test. Test the connection again.")

  defp connection_error(:host_key_not_accepted), do: gettext("No host key is accepted for the target's host and port.")

  defp connection_error(:host_key_rejected),
    do: gettext("The host's key is not the one accepted for it. Test the connection to compare the fingerprints.")

  defp connection_error({:program_missing, program}),
    do: gettext("%{program} is not installed on this server.", program: program)

  defp connection_error({:no_host_keys, output}),
    do: gettext("The host answered with no SSH host keys: %{output}", output: output)

  defp connection_error({:rsync_failed, status, output}),
    do: gettext("rsync exited with status %{status}: %{output}", status: status, output: SSH.remote_output(output))

  defp connection_error(_reason), do: gettext("Could not test the connection.")

  defp can_manage?(user, site), do: Builds.can_manage?(user, site)

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

  defp deploy_strategy("local"), do: :local
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

  defp deploy_configured?(site), do: Builds.deploy_target?(site)

  defp assign_strategy(socket) do
    strategy = deploy_value(socket.assigns.site, :strategy)
    assign(socket, :strategy, if(strategy, do: Atom.to_string(strategy), else: ""))
  end

  # Offered while the installation allows it, and kept for a site that has it
  defp local_delivery_offered?(site),
    do: DeployConfig.local_delivery_allowed?() or deploy_value(site, :strategy) == :local

  defp deploy_summary(%{deploy_config: %{strategy: :local}} = site) do
    case live_domain(site) do
      nil -> gettext("Served by this installation once the live environment has a domain.")
      domain -> gettext("Served by this installation on %{domain}.", domain: domain)
    end
  end

  defp deploy_summary(%{deploy_config: %{strategy: strategy, target: target}})
       when strategy != nil and target not in [nil, ""],
       do: gettext("Deploy via %{strategy} to %{target}", strategy: strategy, target: target)

  defp deploy_summary(_site), do: gettext("No deployment target configured; builds and previews remain available.")

  defp local_delivery_note(%{published_build: version} = site) when is_binary(version) do
    if Site.local_delivery?(site),
      do: gettext("The live environment's domain answers from %{version}, the published build.", version: version),
      else: local_delivery_note(%{site | published_build: nil})
  end

  defp local_delivery_note(_site),
    do:
      gettext(
        "The live environment's domain answers from the published build. Until a build is deployed, it answers as it does now."
      )

  defp live_domain(site) do
    case Enum.find(site.environments, & &1.live) do
      %{domain: domain} when is_binary(domain) and domain != "" -> domain
      _none -> nil
    end
  end

  defp asset_name(%Build{asset_set: nil}), do: gettext("release assets")
  defp asset_name(%Build{asset_set: asset_set}), do: asset_set.name

  defp previewable?(build),
    do: build.status in [:ready, :deployed, :archived] and is_nil(build.pruned_at)

  # A preview opens only on a host of the build's own site
  # (`Brando.SSG.PreviewController`), which with several sites need not be
  # the admin's: link to the build environment's domain, or the live one's.
  # With no such domain there is no host to link to, and no link.
  defp preview_url(build, site, admin_uri) do
    path = "/__ssg_preview__/#{build.preview_token}/"

    if Brando.Tenant.mode() == :multi do
      with %URI{} = uri <- admin_uri,
           domain when is_binary(domain) <- preview_domain(build, site) do
        URI.to_string(%{uri | host: domain, path: path, query: nil, fragment: nil})
      else
        _ -> nil
      end
    else
      path
    end
  end

  defp preview_domain(build, site),
    do: environment_domain(build.environment) || environment_domain(Brando.Tenant.Cache.get_live_env(site.key))

  # A host that would answer 404 is no link: one that does not route, or one
  # of the installation's own, where a preview does not open.
  defp environment_domain(%{domain: domain}) when is_binary(domain) and domain != "" do
    if (not String.contains?(domain, ":") and Brando.Tenant.Cache.get_env_by_domain(domain)) &&
         not Brando.Tenant.InstallationHosts.member?(domain),
       do: domain
  end

  defp environment_domain(_environment), do: nil

  # The CDN in front, or the live domain the installation serves the build on
  defp public_url(build, site, admin_uri) do
    cond do
      build.deploy_config["cdn_url"] not in [nil, ""] ->
        build.deploy_config["cdn_url"]

      build.deploy_config["strategy"] == "local" and site.published_build == build.version ->
        with %URI{} = uri <- admin_uri, domain when is_binary(domain) <- live_domain(site) do
          URI.to_string(%{uri | host: domain, path: "/", query: nil, fragment: nil})
        end

      true ->
        nil
    end
  end

  defp published?(build, site), do: Site.local_delivery?(site) and site.published_build == build.version

  defp build_tone(:deployed), do: "badge--success"
  defp build_tone(:failed), do: "badge--error"
  defp build_tone(_status), do: nil

  defp human_status(:queued), do: gettext("Queued")
  defp human_status(:building), do: gettext("Building")
  defp human_status(:ready), do: gettext("Ready")
  defp human_status(:deployed), do: gettext("Deployed")
  defp human_status(:failed), do: gettext("Failed")
  defp human_status(:archived), do: gettext("Archived")

  # A build stopped by an error partway has URLs it never got to, which did not fail
  defp failed_urls?(build), do: build.status == :failed and build.failed_urls != []

  defp format_datetime(nil), do: "—"
  defp format_datetime(datetime), do: BrandoAdmin.Dates.short(datetime)
end
