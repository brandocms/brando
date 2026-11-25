defmodule BrandoAdmin.Sites.PublishingLive do
  @moduledoc false

  use BrandoAdmin, :live_view
  use BrandoAdmin.Toast
  use Gettext, backend: Brando.Gettext

  # Changing where a site deploys to (its target and webhook, its SSH key and
  # accepted host keys) or what a deploy may delete there, building (which
  # may deploy at once), deploying and rolling back ask for the password, a
  # code or a passkey when the session has not confirmed lately.
  on_mount(
    {BrandoAdmin.Reauth,
     events:
       ~w(save_deploy_config make_deploy_key rotate_deploy_key accept_host_keys confirm_target_review delete_unknown_files remove_keep_path deploy rollback request_build schedule_build)}
  )

  # Builds, deploys and rollbacks report on their rows
  on_mount BrandoAdmin.Work

  # Refusals of a deploy that only someone who may configure publishing can lift
  @set_up_by_configure [:deploy_key_missing, :host_key_not_accepted, :target_not_reviewed]

  alias Brando.Environments.Environment
  alias Brando.Sites.DeployConfig
  alias Brando.Sites.Site
  alias Brando.SSG.Build
  alias Brando.SSG.Builds
  alias Brando.SSG.DeployFiles
  alias Brando.SSG.SSH
  alias Brando.SSG.TargetPaths
  alias Brando.SSG.TargetReview
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
         |> assign_authority()
         |> assign(:default_scheduled_at, default_scheduled_at())
         |> assign(:connection_test, nil)
         |> assign(:connection_test_ref, nil)
         |> assign(:review_error, nil)
         |> assign(:ticked, MapSet.new())
         |> assign(:sandbox, sandbox_owner(socket))
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
        <div :if={!@can_manage? && !@can_configure?} class="environment-notice warning">
          {gettext("Only site administrators and superusers can publish static builds.")}
        </div>

        <section class="environment-panel environment-overview publishing-overview">
          <header>
            <div>
              <h2>{@site.name}</h2>
              <p>{deploy_summary(@site, @can_configure?)}</p>
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

        <section :if={!@can_configure?} class="environment-panel" id="publishing-settings">
          <h2>{gettext("Deployment target")}</h2>
          <dl class="publishing-settings">
            <div>
              <dt>{gettext("Strategy")}</dt>
              <dd>{strategy_label(@site)}</dd>
            </div>
            <div :if={deploy_configured?(@site)}>
              <dt>{gettext("Automatic deployment")}</dt>
              <dd>{if auto_deploy?(@site), do: gettext("On"), else: gettext("Off")}</dd>
            </div>
          </dl>
          <p>{gettext("Someone who may configure publishing changes where and how the site deploys.")}</p>
        </section>

        <section :if={@can_configure?} class="environment-panel">
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
            <div :if={@strategy == "rsync"} class="publishing-htaccess-option">
              <label class="environment-check">
                <input type="checkbox" name="deploy[htaccess]" value="true" checked={deploy_value(@site, :htaccess)} />
                <span>{gettext("The host is Apache or LiteSpeed")}</span>
              </label>
              <p>
                {gettext(
                  "Each deploy writes the redirects, the 404 page and caching into Brando's block in the target's .htaccess, and leaves _redirects.json out. The host's own lines stay. Open the site after the first deploy: a host that forbids these directives answers 500."
                )}
              </p>
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
            <button type="submit" class="btn">{gettext("Save deployment settings")}</button>
          </form>
        </section>

        <.ssh_access
          :if={@can_configure? && rsync_saved?(@site)}
          public_key={@public_key}
          key_problem={@key_problem}
          connection_test={@connection_test}
        />

        <.target_files
          :if={@target}
          target={@target}
          ticked={@ticked}
          review_error={@review_error}
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

          <div
            :if={no_preview_host?(@builds, @site, @admin_uri)}
            id="publishing-no-preview-host"
            class="environment-notice warning publishing-no-preview-host"
          >
            <div>
              {gettext(
                "This site has no host for previews. An environment domain routed to this installation, or the installation's preview_host setting, gives it one."
              )}
            </div>
            <a
              href="https://hexdocs.pm/brando/tenancy_and_environments.html#preview-hosts"
              target="_blank"
              rel="noopener"
            >
              {gettext("Preview hosts in the guide")} ↗
            </a>
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
                      :if={previewable?(build) && Builds.preview_url(build, @site, @admin_uri)}
                      class="btn btn--sm"
                      href={Builds.preview_url(build, @site, @admin_uri)}
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
                    <%!-- The log names the server and its paths --%>
                    <details :if={(@can_configure? && build.build_log != "") || build.failed_urls != []}>
                      <summary>{if @can_configure?, do: gettext("Log"), else: gettext("Failed URLs")}</summary>
                      <pre :if={@can_configure?}>{build.build_log}</pre>
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
          disabled={@connection_test == :running}
        >
          {if @connection_test == :running, do: gettext("Testing…"), else: gettext("Test connection")}
        </button>
        <button
          :if={@public_key || @key_problem == :unreadable_key}
          type="button"
          class="btn"
          phx-click="rotate_deploy_key"
          data-confirm={
            gettext(
              "Replace the site's key with a new one? Deploys use the new key at once: add it to the host before the next deploy. The old key stays authorized on the host until you remove it from authorized_keys there."
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
          phx-click="make_deploy_key"
        >
          {gettext("Make key")}
        </button>
      </div>

      <.connection_result :if={is_tuple(@connection_test)} result={@connection_test} />
    </section>
    """
  end

  attr :target, :map
  attr :ticked, :any
  attr :review_error, :any
  attr :can_deploy?, :boolean

  # What a deploy may delete on the target (Brando.SSG.TargetReview)
  defp target_files(assigns) do
    assigns =
      assign(assigns,
        entries:
          if(assigns.target.found, do: TargetPaths.top_level(assigns.target.found.paths, assigns.target.keep), else: [])
      )

    ~H"""
    <section class="environment-panel publishing-review" id="publishing-review">
      <h2>{gettext("Files on the target")}</h2>
      <p>
        {gettext(
          "A deploy deletes only files Brando uploaded or that you confirmed here, and never a path on the keep list. Other files on the target stay."
        )}
      </p>

      <div :if={@review_error} class="alert environment-hint" role="alert" data-testid="review-error">
        <.icon name="triangle-alert" />
        <span>{review_error(@review_error)}</span>
      </div>

      <div :if={!@target.reviewed && is_nil(@target.found)} class="alert environment-hint" role="status">
        <.icon name="info" />
        <span>
          {gettext(
            "Review the target before its first deploy: once the connection test connects, it lists what the target holds."
          )}
        </span>
      </div>

      <div :if={@target.reviewed && @entries == []} class="alert environment-hint" role="status" data-testid="target-reviewed">
        <.icon name="circle-check" />
        <span :if={is_nil(@target.found)}>
          {gettext("Reviewed. The next deploy deletes what you confirmed, and nothing else Brando did not upload.")}
        </span>
        <span :if={@target.found}>
          {gettext("Reviewed. The last deploy found no files on the target that Brando did not put there.")}
        </span>
      </div>

      <form
        :if={@target.found && (!@target.reviewed || @entries != [])}
        id="target-files"
        class="publishing-review-files"
        phx-change="tick_target_files"
        data-kind={if @target.reviewed, do: "unknown", else: "review"}
      >
        <div>
          <h3>
            {if @target.reviewed,
              do: gettext("The target holds files Brando did not put there"),
              else: gettext("Review before the first deploy")}
          </h3>
          <p :if={!@target.reviewed}>
            {gettext(
              "The target holds these entries. Tick what to keep: the first deploy deletes the rest. Deeper paths can be added to the keep list below."
            )}
          </p>
          <p :if={@target.reviewed}>
            {gettext("Deploys leave them. Keep the ticked ones, or delete the rest with a new deploy of the deployed build.")}
          </p>
        </div>

        <div :if={@entries == []} class="environment-notice">{gettext("The target is empty.")}</div>

        <ul :if={@entries != []} class="publishing-entries">
          <li :for={entry <- @entries}>
            <label class="environment-check">
              <input
                type="checkbox"
                name="keep[]"
                value={entry.name}
                checked={entry.kept || MapSet.member?(@ticked, entry.name)}
                disabled={entry.kept}
              />
              <code>{TargetReview.display(entry.name)}</code>
            </label>
            <span class="publishing-entry-files">
              {ngettext("%{count} file", "%{count} files", entry.files)}
            </span>
            <span :if={entry.kept} class="badge">{gettext("Kept")}</span>
            <span :if={!entry.kept && !TargetPaths.keep_entry?(entry.name)} class="publishing-entry-note">
              {gettext("cannot go on the keep list: tick it to leave it on the target")}
            </span>
          </li>
        </ul>

        <details :if={@target.found[:htaccess]} class="publishing-htaccess">
          <summary>.htaccess</summary>
          <.htaccess value={@target.found.htaccess} />
        </details>

        <div class="environment-actions publishing-review-actions">
          <button
            :if={!@target.reviewed}
            type="button"
            class="btn btn--primary"
            phx-click="confirm_target_review"
            phx-value-digest={@target.found.digest}
            data-confirm={gettext("Confirm? The first deploy deletes every entry you did not tick.")}
            data-confirm-ok={gettext("Confirm")}
          >
            {gettext("Confirm")}
          </button>
          <button
            :if={@target.reviewed}
            type="button"
            class="btn"
            phx-click="keep_unknown_files"
          >
            {gettext("Keep ticked")}
          </button>
          <button
            :if={@target.reviewed}
            type="button"
            class="btn btn--danger"
            disabled={!@can_deploy?}
            phx-click="delete_unknown_files"
            phx-value-digest={@target.found.digest}
            data-confirm={gettext("Delete the entries you did not tick? A deploy of the deployed build deletes them.")}
            data-confirm-ok={gettext("Delete")}
          >
            {gettext("Delete the rest")}
          </button>
        </div>
      </form>

      <div class="publishing-keep">
        <div>
          <h3>{gettext("Keep list")}</h3>
          <p>{gettext("Paths relative to the target, a directory ending in /. A deploy never deletes them.")}</p>
        </div>
        <ul class="publishing-entries">
          <li :for={path <- @target.keep}>
            <code>{path}</code>
            <button
              type="button"
              class="btn btn--sm"
              phx-click="remove_keep_path"
              phx-value-path={path}
            >
              {gettext("Remove")}
            </button>
          </li>
        </ul>
        <form id="add-keep-path" class="publishing-keep-add" phx-submit="add_keep_path">
          <label>
            <span>{gettext("Path to keep")}</span>
            <input name="keep_path" placeholder="uploads/" autocomplete="off" spellcheck="false" />
          </label>
          <button type="submit" class="btn">{gettext("Add")}</button>
        </form>
      </div>
    </section>
    """
  end

  attr :value, :any

  defp htaccess(%{value: {:ok, text}} = assigns) do
    assigns = assign(assigns, :text, if(String.valid?(text), do: text, else: inspect(text)))

    ~H"""
    <pre>{@text}</pre>
    """
  end

  defp htaccess(%{value: :too_large} = assigns) do
    ~H"""
    <p>{gettext("It is larger than 256 KB and is not shown.")}</p>
    """
  end

  defp htaccess(assigns) do
    ~H"""
    <p>{gettext("It could not be fetched.")}</p>
    """
  end

  attr :result, :any

  defp connection_result(%{result: {:error, reason}} = assigns) do
    assigns = assign(assigns, :message, connection_error(reason))

    ~H"""
    <div class="alert environment-hint" role="alert" data-testid="connection-result">
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
          phx-click="accept_host_keys"
          data-confirm={gettext("Accept these host keys for %{host}?", host: host_label(@test))}
          data-confirm-ok={gettext("Accept host key")}
        >
          {gettext("Accept host key")}
        </button>
      </div>

      <div :if={@test.dry_run == :ok} class="alert environment-hint" role="status" data-testid="dry-run-ok">
        <.icon name="circle-check" />
        <span>{gettext("Connected: ssh, the site's key and rsync on the host work.")}</span>
      </div>
      <div :if={match?({:error, _}, @test.dry_run)} class="alert environment-hint" role="alert" data-testid="dry-run-failed">
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
      retention_count: parse_integer(params["retention_count"], 10),
      htaccess: params["htaccess"] == "true"
    }

    user = socket.assigns.current_user

    case Builds.update_deploy_config(socket.assigns.site, attrs, user) do
      {:ok, site} ->
        # The key is made with the first rsync settings; where it may not be
        # kept, or one is there that cannot be read, the panel says why
        with true <- rsync_saved?(site),
             {:error, reason} when reason not in [:served, :unsafe_path, :unreadable_key] <- SSH.ensure_key(site, user),
             do: toast_error(socket, key_error(reason))

        send(self(), {:toast, gettext("Static deployment settings saved")})
        {:noreply, socket |> forget_connection_test() |> refresh() |> assign_strategy()}

      {:error, %Ecto.Changeset{} = changeset} ->
        toast_error(socket, BrandoAdmin.Utils.format_changeset_errors(changeset))

      {:error, :forbidden} ->
        toast_error(socket, connection_error(:forbidden))
    end
  end

  # Keeps a key made since the screen showed none
  def handle_event("make_deploy_key", _params, socket) do
    case SSH.ensure_key(socket.assigns.site, socket.assigns.current_user) do
      {:ok, _public_key} -> {:noreply, socket |> forget_connection_test() |> refresh()}
      {:error, reason} -> toast_error(socket, key_error(reason))
    end
  end

  def handle_event("rotate_deploy_key", _params, socket) do
    case SSH.rotate_key(socket.assigns.site, socket.assigns.current_user) do
      {:ok, _public_key} ->
        send(self(), {:toast, gettext("The site has a new SSH key")})
        {:noreply, socket |> forget_connection_test() |> refresh()}

      {:error, reason} ->
        toast_error(socket, key_error(reason))
    end
  end

  # Runs beside the screen: the host may take its time to answer
  def handle_event("test_connection", _params, %{assigns: %{connection_test: :running}} = socket),
    do: {:noreply, socket}

  def handle_event("test_connection", _params, socket) do
    site = socket.assigns.site
    user = socket.assigns.current_user
    sandbox = socket.assigns.sandbox
    ref = make_ref()

    # Once it connects, an unreviewed target is listed for its review
    {:noreply,
     socket
     |> assign(connection_test: :running, connection_test_ref: ref)
     |> start_async(:connection_test, fn ->
       if sandbox, do: Phoenix.Ecto.SQL.Sandbox.allow(sandbox, Ecto.Adapters.SQL.Sandbox)

       result =
         case SSH.test_connection(site, user) do
           {:ok, %{dry_run: :ok}} = result -> {result, TargetReview.review(site, user)}
           result -> {result, nil}
         end

       {ref, result}
     end)}
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

  # The ticks are the server's: Confirm, Keep and Delete act on them
  def handle_event("tick_target_files", params, socket),
    do: {:noreply, assign(socket, :ticked, MapSet.new(List.wrap(params["keep"])))}

  def handle_event("confirm_target_review", %{"digest" => digest}, socket) do
    socket.assigns.site
    |> TargetReview.confirm(socket.assigns.current_user, :review, digest, MapSet.to_list(socket.assigns.ticked))
    |> target_changed(socket, gettext("The target is reviewed. Deploys delete only what Brando uploads from now on."))
  end

  def handle_event("keep_unknown_files", _params, socket) do
    socket.assigns.site
    |> TargetReview.keep(socket.assigns.current_user, MapSet.to_list(socket.assigns.ticked))
    |> target_changed(socket, gettext("The ticked entries are on the keep list"))
  end

  def handle_event("delete_unknown_files", %{"digest" => digest}, socket) do
    socket.assigns.site
    |> TargetReview.delete_unknown(socket.assigns.current_user, digest, MapSet.to_list(socket.assigns.ticked))
    |> target_changed(
      socket,
      gettext("A deploy of the deployed build is queued: it deletes the entries you did not tick")
    )
  end

  def handle_event("add_keep_path", %{"keep_path" => path}, socket) do
    socket.assigns.site
    |> TargetReview.add_keep_path(socket.assigns.current_user, String.trim(path))
    |> target_changed(socket, gettext("Path added to the keep list"))
  end

  def handle_event("remove_keep_path", %{"path" => path}, socket) do
    socket.assigns.site
    |> TargetReview.remove_keep_path(socket.assigns.current_user, path)
    |> target_changed(socket, gettext("Path removed from the keep list"))
  end

  # The job reports on the build's row, or as a toast elsewhere (BrandoAdmin.Work)
  def handle_event(action, %{"id" => id}, socket) when action in ["deploy", "rollback"] do
    user = socket.assigns.current_user

    with true <- can_manage?(socket.assigns.current_user, socket.assigns.site),
         {build_id, ""} <- Integer.parse(id),
         %Build{site_id: site_id} = build <- Enum.find(socket.assigns.builds, &(&1.id == build_id)),
         true <- site_id == socket.assigns.site.id,
         :ok <- target_set_up(socket.assigns.site, build),
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
      {:error, :site_not_found} -> {:noreply, redirect(socket, to: "/admin")}
      {:error, reason} when reason in @set_up_by_configure -> toast_error(socket, set_up_by_configure(reason))
      _error -> toast_error(socket, gettext("Could not queue the publishing action."))
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:ssg_build_updated, _build}, socket), do: {:noreply, refresh(socket)}

  # A grant changed while the screen is open (`BrandoAdmin.Authorization`)
  def refresh_authorization(%{assigns: %{socket_connected: true}} = socket),
    do: socket |> assign_authority() |> refresh()

  def refresh_authorization(socket), do: socket

  # An answer for settings saved since, here or elsewhere, or a key rotated
  # here since, is dropped
  @impl Phoenix.LiveView
  def handle_async(:connection_test, {:ok, {ref, {result, review}}}, %{assigns: %{connection_test_ref: ref}} = socket) do
    review_error =
      case review do
        {:error, reason} -> reason
        _listed -> nil
      end

    {:noreply,
     socket
     |> assign(connection_test: if(tested_stored?(result, socket.assigns.site), do: result), review_error: review_error)
     |> refresh()}
  end

  def handle_async(:connection_test, {:ok, _dropped}, socket), do: {:noreply, socket}

  def handle_async(:connection_test, {:exit, _reason}, %{assigns: %{connection_test: :running}} = socket),
    do: {:noreply, assign(socket, :connection_test, {:error, :test_failed})}

  def handle_async(:connection_test, {:exit, _reason}, socket), do: {:noreply, socket}

  # The screen shows what is stored now, whichever way it went
  defp target_changed(result, socket, done) do
    case result do
      {:error, reason} ->
        socket = refresh(socket)
        toast_error(socket, review_error(reason))

      _done ->
        send(self(), {:toast, done})
        {:noreply, socket |> assign(ticked: MapSet.new(), review_error: nil) |> refresh()}
    end
  end

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
    auto_deploy? = params["auto_deploy"] == "true"

    with true <- can_manage?(socket.assigns.current_user, socket.assigns.site),
         %Environment{} = environment <- environment(socket, params["environment_id"]),
         # A build that deploys itself is refused as its deploy would be
         :ok <- if(auto_deploy?, do: target_set_up(socket.assigns.site), else: :ok),
         {:ok, build} <-
           Builds.request_build(socket.assigns.site, environment,
             creator_id: socket.assigns.current_user.id,
             note: blank_to_nil(params["note"]),
             auto_deploy: auto_deploy?,
             scheduled_at: scheduled_at
           ) do
      # An immediate build reports on its row (BrandoAdmin.Work); a scheduled one waits
      if scheduled_at, do: send(self(), {:toast, gettext("Scheduled static build %{version}", version: build.version)})
      {:noreply, refresh(socket)}
    else
      {:error, :site_not_found} -> {:noreply, redirect(socket, to: "/admin")}
      {:error, reason} when reason in @set_up_by_configure -> toast_error(socket, set_up_by_configure(reason))
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

  # Publishing (build, deploy, schedule) and configuring it are apart
  defp assign_authority(socket) do
    user = socket.assigns.current_user
    site = socket.assigns.site

    assign(socket, can_manage?: can_manage?(user, site), can_configure?: Builds.can_configure?(user, site))
  end

  # A site deleted while the screen is open goes where the mount sends it
  defp refresh(socket) do
    case Registry.get_site(socket.assigns.site.id) do
      nil ->
        redirect(socket, to: "/admin")

      site ->
        socket
        |> assign(:site, site)
        |> assign(:environments, site.environments |> Enum.sort_by(&{not &1.live, &1.name}))
        |> assign(:builds, Builds.list_builds(site))
        |> assign_key(site)
        |> assign_target(site)
    end
  end

  # Remote file names, for those who may configure the site's publishing
  defp assign_target(socket, site) do
    target =
      with true <- socket.assigns.can_configure? and rsync_saved?(site),
           {:ok, %{} = target} <- TargetReview.status(site, socket.assigns.current_user) do
        target
      else
        _none -> nil
      end

    # Ticks are for the list they were made on
    digest = fn target -> target && target.found && target.found.digest end

    ticked =
      if digest.(target) == digest.(socket.assigns[:target]),
        do: socket.assigns[:ticked],
        else: default_ticked(target)

    assign(socket, target: target, ticked: ticked || MapSet.new())
  end

  # The host's .htaccess is kept unless the admin says otherwise
  defp default_ticked(%{reviewed: false, found: %{paths: paths}}),
    do: if(".htaccess" in paths, do: MapSet.new([".htaccess"]), else: MapSet.new())

  defp default_ticked(_target), do: MapSet.new()

  # The public key, for those who may change it; the private key stays in its file
  defp assign_key(socket, site) do
    {public_key, problem} =
      if socket.assigns.can_configure? and rsync_saved?(site) do
        case DeployFiles.check_location(site) do
          :ok -> site |> SSH.public_key() |> key_or_problem()
          {:error, problem} -> {nil, problem}
        end
      else
        {nil, nil}
      end

    assign(socket, public_key: public_key, key_problem: problem)
  end

  defp forget_connection_test(socket), do: assign(socket, connection_test: nil, connection_test_ref: nil)

  defp tested_stored?({:ok, %{target: target, port: port}}, site) do
    case Registry.get_site(site.id) do
      %{deploy_config: %{strategy: :rsync, target: ^target} = config} -> (config.port || 22) == port
      _changed -> false
    end
  end

  defp tested_stored?({:error, _reason}, _site), do: true

  defp key_or_problem({:ok, public_key}), do: {public_key, nil}
  defp key_or_problem({:error, :no_key}), do: {nil, nil}
  defp key_or_problem({:error, :unreadable_key}), do: {nil, :unreadable_key}

  defp rsync_saved?(%{deploy_config: %{strategy: :rsync, target: target}}) when target not in [nil, ""], do: true
  defp rsync_saved?(_site), do: false

  defp host_label(%{target: target, port: 22}), do: DeployConfig.rsync_host(target)

  defp host_label(%{target: target, port: port}),
    do: gettext("%{host}, port %{port}", host: DeployConfig.rsync_host(target), port: port)

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

  defp connection_error(:host_keys_changed),
    do: gettext("Other host keys were accepted after the test. Test the connection again.")

  defp connection_error(:deploy_running), do: review_error(:deploy_running)
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

  # Making or rotating the key
  defp key_error(reason) when reason in [:served, :unsafe_path], do: key_problem_message(reason)
  defp key_error(:forbidden), do: connection_error(:forbidden)
  defp key_error(_reason), do: gettext("The site's SSH key could not be written.")

  defp review_error(:forbidden), do: connection_error(:forbidden)
  defp review_error(:not_rsync), do: connection_error(:not_rsync)

  defp review_error(:stale_listing),
    do: gettext("What the target holds changed since this page showed it. Look at the current list before you confirm.")

  defp review_error(:target_changed),
    do: gettext("The target, port or accepted host keys changed. Test the connection again.")

  defp review_error(:deploy_running), do: gettext("A deploy is running. Try again when it has finished.")

  defp review_error({:listing_cut_short, count, limit}),
    do:
      gettext("The target holds %{count} paths, more than the %{limit} Brando lists, so it cannot be reviewed here.",
        count: count,
        limit: limit
      )

  defp review_error(:invalid_keep_path),
    do: gettext("A path to keep is relative, of letters, digits and . _ ~ + @ , - and spaces, with no . or .. segment.")

  defp review_error({:invalid_keep_paths, changeset}), do: BrandoAdmin.Utils.format_changeset_errors(changeset)

  defp review_error({:target_state_unreadable, _reason}),
    do: gettext("The target's state could not be read. Test the connection to review the target again.")

  defp review_error(reason), do: gettext("Could not list the target: %{reason}", reason: connection_error(reason))

  defp can_manage?(user, site), do: Builds.can_manage?(user, site)

  # A deploy the target refuses until someone who may configure publishing
  # sets it up is said at once, not in a log only they may read: a deploy of
  # `build`, or of a build made now. The settings as stored: they may have
  # changed since the screen showed them.
  defp target_set_up(site, build \\ nil) do
    with %Site{} = stored <- Registry.get_site(site.id),
         {:error, reason} when reason in @set_up_by_configure <-
           if(build, do: TargetReview.deployable(stored, build), else: TargetReview.deployable(stored)) do
      {:error, reason}
    else
      nil -> {:error, :site_not_found}
      _deployable -> :ok
    end
  end

  defp set_up_by_configure(:deploy_key_missing),
    do:
      gettext(
        "The site has no SSH key yet. Someone who may configure publishing makes one here and adds it to the host before the first deploy."
      )

  defp set_up_by_configure(:host_key_not_accepted),
    do:
      gettext(
        "No host key is accepted for the target. Someone who may configure publishing tests the connection here and accepts the host's key."
      )

  defp set_up_by_configure(:target_not_reviewed),
    do:
      gettext(
        "The target is not reviewed. Someone who may configure publishing reviews what it holds here before the first deploy."
      )

  # An E2E test's SQL sandbox, for the reads of the connection test's task
  defp sandbox_owner(socket) do
    if Application.get_env(Brando.otp_app(), :sql_sandbox, false), do: get_connect_info(socket, :user_agent)
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

  # The target is for those who may configure publishing: it names the
  # server and its path
  defp deploy_summary(site, false = _can_configure?) do
    if deploy_configured?(site) and deploy_value(site, :strategy) in [:rsync, :s3],
      do: gettext("Deploys via %{strategy}", strategy: strategy_label(site)),
      else: deploy_summary(site)
  end

  defp deploy_summary(site, true), do: deploy_summary(site)

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

  defp strategy_label(site) do
    case deploy_value(site, :strategy) do
      :local -> gettext("Served by this installation")
      :rsync -> "Rsync"
      :s3 -> "Amazon S3"
      :cloudflare_pages -> "Cloudflare Pages"
      nil -> gettext("Build and preview only")
    end
  end

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

  # A previewable build with no host to open its preview on
  # (`Brando.SSG.Builds.preview_url/3`), said once for the screen. With the
  # preview host pattern set, a build whose environment was deleted has no
  # link whatever the site's hosts are, so it says nothing about them
  defp no_preview_host?(builds, site, admin_uri) do
    pattern? = Brando.SSG.PreviewHost.enabled?()

    Enum.any?(builds, fn build ->
      previewable?(build) and not (pattern? and is_nil(build.environment)) and
        is_nil(Builds.preview_url(build, site, admin_uri))
    end)
  end

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
