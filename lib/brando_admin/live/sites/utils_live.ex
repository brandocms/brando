defmodule BrandoAdmin.Sites.UtilsLive do
  @moduledoc false
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  import Phoenix.Component

  alias Brando.Authorization.{Configuration, Engine, Scope}
  alias Brando.Images
  alias Brando.Search
  alias BrandoAdmin.Components.AuthorizationTools
  alias BrandoAdmin.Components.SystemCheck

  on_mount({BrandoAdmin.LiveView.Form, {:hooks_toast, __MODULE__}})

  def mount(params, %{"user_token" => token}, socket) do
    if connected?(socket) do
      {:ok,
       socket
       |> assign(:socket_connected, true)
       |> assign_current_user(token)
       |> assign_sitemap()
       |> set_admin_locale()
       |> assign_info()
       |> assign(:loose_blocks, Brando.Content.BlockAudit.count_loose())
       |> assign_search_index()
       |> subscribe_image_tasks()
       |> assign_image_tasks()
       |> assign_authorization_tools(params)
       |> assign(:doctor_sandbox, sandbox_owner(socket))
       |> start_system_check()}
    else
      {:ok, assign(socket, :socket_connected, false)}
    end
  end

  defp assign_sitemap(socket) do
    sitemap_path = Path.join([Brando.Tenant.Storage.current_media_root(), "sitemaps", "sitemap.xml.gz"])

    sitemap_last_updated =
      if File.exists?(sitemap_path) do
        {:ok, stat} = File.stat(sitemap_path, time: :posix)

        stat.mtime
        |> DateTime.from_unix!()
        |> DateTime.shift_zone!(Brando.timezone())
      end

    assign(socket, :sitemap_last_updated, sitemap_last_updated)
  end

  # The search index of this site and environment: how many documents it
  # holds, when it was last rebuilt, and a rebuild's progress, which its job
  # broadcasts.
  defp assign_search_index(socket) do
    if connected?(socket) and !socket.assigns[:search_index],
      do: Phoenix.PubSub.subscribe(Brando.pubsub(), Search.topic())

    state = if Search.rebuild_running?(), do: :queued, else: :idle

    assign(socket, :search_index, %{
      state: state,
      done: 0,
      total: 0,
      count: Search.count(),
      rebuilt_at: Search.rebuilt_at()
    })
  end

  # Recreate changed images reports how many images it kept and how many it
  # recreated; the latest run's counts show under the tool.
  defp subscribe_image_tasks(socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Brando.pubsub(), Images.Processing.topic())
    assign(socket, :image_run, nil)
  end

  defp assign_image_tasks(socket) do
    recreate_sizes? = Images.Processing.image_maintenance_running?("recreate_sizes")
    recreate_changed_sizes? = Images.Processing.image_maintenance_running?("recreate_changed_sizes")

    socket
    |> assign(:image_tasks, %{
      # Either recreate run blocks both buttons; they queue the same jobs.
      "recreate_sizes" => recreate_sizes? or recreate_changed_sizes?,
      "dominant_colors" => Images.Processing.image_maintenance_running?("dominant_colors")
    })
    |> assign(:changed_images, Images.Processing.count_changed_images())
  end

  defp assign_info(socket) do
    info = %{
      version: Brando.version(),
      timezone: Brando.timezone(),
      locale: Gettext.get_locale(),
      concurrency: System.schedulers_online(),
      concurrent_image_jobs: Brando.config(:concurrent_image_jobs) || 1
    }

    assign(socket, :info, info)
  end

  def render(%{socket_connected: false} = assigns) do
    ~H"""
    """
  end

  def render(assigns) do
    ~H"""
    <div class="utils-workspace">
      <header class="utils-page-heading">
        <div>
          <span class="utils-eyebrow">{gettext("Configuration")}</span>
          <h1>{gettext("Utilities")}</h1>
          <p>{gettext("Administrative tools for this workspace.")}</p>
        </div>
        <span class="utils-version">Brando {@info.version}</span>
      </header>

      <AuthorizationTools.workspace
        :if={@authorization_tools?}
        scope={@configuration_scope}
        scope_label={@configuration_scope_label}
        legacy_mode?={@legacy_mode?}
        report={@migration_report}
        busy={@authorization_busy}
        message={@authorization_message}
        error={@authorization_error}
        backfilled?={@authorization_backfilled?}
        uploads={@uploads}
        preview={@configuration_preview}
        download={@configuration_download}
      />

      <SystemCheck.card results={@system_check} failed={@system_check_failed} socket={@socket} />

      <section class="utils-maintenance" aria-labelledby="maintenance-title">
        <div class="utils-section-heading">
          <div>
            <h2 id="maintenance-title">
              {gettext("Maintenance")}
            </h2>
          </div>
        </div>
        <div class="utils-maintenance-list">
          <article id="utils-identifiers">
            <div>
              <h3>{gettext("Content identifiers")}</h3><p>
                {gettext("Update the identifiers used to reference content.")}
              </p>
            </div>
            <button type="button" class="utils-button" phx-click="sync_identifiers" phx-disable-with={gettext("Syncing…")}>{gettext(
              "Sync identifiers"
            )}</button>
          </article>
          <article id="utils-search-index">
            <div>
              <h3>{gettext("Search index")}</h3><p>
                {gettext(
                  "Index every entry again for the admin search. Saving keeps it up to date; rebuild after upgrading or importing content."
                )}
              </p>
              <%!-- Progress is announced; the other rows' notes are not live regions. --%>
              <span id="utils-search-index-state" aria-live="polite">
                <small :if={@search_index.state == :queued}>{gettext("Waiting to start")}</small>
                <small :if={@search_index.state == :running}>
                  {gettext("Indexing… %{done} of %{total} entries", done: @search_index.done, total: @search_index.total)}
                </small>
                <small :if={@search_index.state == :failed}>{gettext("The rebuild failed. Check the application logs.")}</small>
                <%= if @search_index.state in [:idle, :done] and is_integer(@search_index.count) do %>
                  <small>
                    {ngettext("%{count} entry in the index", "%{count} entries in the index", @search_index.count)}
                  </small>
                  <small :if={@search_index.rebuilt_at} id="utils-search-index-rebuilt">
                    {gettext("Last rebuilt: %{date}", date: BrandoAdmin.Dates.long(@search_index.rebuilt_at))}
                  </small>
                  <small :if={!@search_index.rebuilt_at} id="utils-search-index-rebuilt" class="utils-empty-status">
                    {gettext("Never rebuilt")}
                  </small>
                <% end %>
                <small :if={@search_index.state in [:idle, :done] and is_nil(@search_index.count)} class="utils-empty-status">
                  {gettext("Not set up: the brando_212 migration has not run")}
                </small>
              </span>
            </div>
            <button
              type="button"
              class="utils-button"
              phx-click="rebuild_search_index"
              disabled={@search_index.state in [:queued, :running] or is_nil(@search_index.count)}
            >
              {gettext("Rebuild search index")}
            </button>
          </article>
          <article id="utils-loose-blocks">
            <div>
              <h3>{gettext("Loose blocks")}</h3><p>
                {gettext("Find blocks no entry uses any more, and remove the ones nothing can bring back.")}
              </p>
            </div>
            <.link
              navigate={Brando.routes().admin_live_path(@socket, BrandoAdmin.Sites.BlockAuditLive)}
              class="utils-button"
            >
              {gettext("Review loose blocks")}
              <span :if={@loose_blocks > 0} class="utils-button-count">{@loose_blocks}</span>
            </.link>
          </article>
          <article id="utils-sitemap">
            <div>
              <h3>{gettext("Sitemap")}</h3><p>
                {gettext("Regenerate the sitemap from published content.")}
              </p>
              <small :if={@sitemap_last_updated}>
                {gettext("Last generated: %{last_updated}",
                  last_updated: BrandoAdmin.Dates.long(@sitemap_last_updated)
                )}
              </small>
              <small :if={!@sitemap_last_updated} class="utils-empty-status">{gettext("Not generated")}</small>
            </div>
            <button type="button" class="utils-button" phx-click="generate_sitemap" phx-disable-with={gettext("Generating…")}>{gettext(
              "Generate sitemap"
            )}</button>
          </article>
          <article id="utils-image-sizes">
            <div>
              <h3>{gettext("Image sizes")}</h3><p>
                {gettext("Recreate the sizes and formats of images from their originals, using the current image settings.")}
              </p>
              <small :if={@image_tasks["recreate_sizes"]}>{gettext("Running in the background")}</small>
              <small :if={!@image_tasks["recreate_sizes"] && @changed_images > 0}>
                {ngettext(
                  "%{count} image was made with older settings",
                  "%{count} images were made with older settings",
                  @changed_images
                )}
              </small>
              <small :if={!@image_tasks["recreate_sizes"] && @changed_images == 0} class="utils-empty-status">
                {gettext("All images match their settings")}
              </small>
              <small :if={@image_run} id="utils-image-run">
                {ngettext(
                  "%{count} image already matched its settings",
                  "%{count} images already matched their settings",
                  @image_run.adopted
                )} · {ngettext("%{count} image recreated", "%{count} images recreated", @image_run.recreated)}
              </small>
            </div>
            <div class="utils-row-actions">
              <button
                type="button"
                class="utils-button"
                phx-click="recreate_image_sizes"
                disabled={@image_tasks["recreate_sizes"]}
                data-confirm-title={gettext("Recreate the sizes of every image?")}
                data-confirm={gettext("This runs in the background and can take a long time for a large library.")}
                data-confirm-ok={gettext("Recreate sizes")}
              >
                {gettext("Recreate image sizes")}
              </button>
              <button
                type="button"
                class={["utils-button", @changed_images > 0 && "primary"]}
                phx-click="recreate_changed_image_sizes"
                disabled={@image_tasks["recreate_sizes"] || @changed_images == 0}
                data-confirm-title={gettext("Recreate the sizes of changed images?")}
                data-confirm={gettext("Only images made with older settings are recreated. This runs in the background.")}
                data-confirm-ok={gettext("Recreate sizes")}
              >
                {gettext("Recreate changed images")}
              </button>
            </div>
          </article>
          <article id="utils-dominant-colors">
            <div>
              <h3>{gettext("Dominant colors")}</h3><p>
                {gettext("Read the dominant color of every image again. It is used as a placeholder while images load.")}
              </p>
              <small :if={@image_tasks["dominant_colors"]}>{gettext("Running in the background")}</small>
            </div>
            <button
              type="button"
              class="utils-button"
              phx-click="recalculate_dominant_colors"
              disabled={@image_tasks["dominant_colors"]}
              data-confirm-title={gettext("Read the dominant color of every image again?")}
              data-confirm={gettext("This runs in the background.")}
              data-confirm-ok={gettext("Recalculate colors")}
            >
              {gettext("Recalculate colors")}
            </button>
          </article>
        </div>
      </section>
      <footer class="utils-system-info" aria-label={gettext("System information")}>
        <h2>{gettext("System information")}</h2>
        <dl>
          <div>
            <dt>{gettext("Timezone")}</dt><dd>{@info.timezone}</dd>
          </div>
          <div>
            <dt>{gettext("Locale")}</dt><dd>{@info.locale}</dd>
          </div>
          <div>
            <dt>{gettext("Concurrency")}</dt><dd>{@info.concurrency}</dd>
          </div>
          <div>
            <dt>{gettext("Image jobs")}</dt><dd>{@info.concurrent_image_jobs}</dd>
          </div>
        </dl>
      </footer>
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

  def handle_event("authorization_" <> event, params, socket) do
    if Configuration.allowed?(socket.assigns.configuration_scope) do
      authorization_event(event, params, socket)
    else
      {:noreply, redirect(socket, to: "/admin/access-denied")}
    end
  end

  # Re-runs the system check; "refresh" is a read for authorization
  def handle_event("refresh", _, socket) do
    if socket.assigns.system_check do
      {:noreply, start_system_check(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("sync_identifiers", _, socket) do
    Brando.Blueprint.Identifier.sync()
    send(self(), {:toast, gettext("Identifiers synced.")})

    {:noreply, socket}
  end

  def handle_event("rebuild_search_index", _, socket) do
    case Search.queue_rebuild(socket.assigns.current_user) do
      {:ok, _job} ->
        {:noreply, update(socket, :search_index, &queued/1)}

      {:error, :already_running} ->
        send(self(), {:toast, gettext("This is already running.")})
        {:noreply, update(socket, :search_index, &queued/1)}

      {:error, _reason} ->
        send(self(), {:toast, gettext("The operation could not be completed. Check the application logs and try again.")})
        {:noreply, socket}
    end
  end

  def handle_event("generate_sitemap", _, socket) do
    Brando.Sitemap.generate_sitemap()
    send(self(), {:toast, gettext("Generated sitemap.")})

    {:noreply, assign_sitemap(socket)}
  end

  def handle_event("recreate_image_sizes", _, socket) do
    socket.assigns.current_user
    |> Images.Processing.recreate_sizes_for_images()
    |> image_task_started(socket, gettext("Recreating image sizes in the background."))
  end

  def handle_event("recreate_changed_image_sizes", _, socket) do
    socket.assigns.current_user
    |> Images.Processing.recreate_sizes_for_changed_images()
    |> image_task_started(socket, gettext("Recreating changed image sizes in the background."))
  end

  def handle_event("recalculate_dominant_colors", _, socket) do
    socket.assigns.current_user
    |> Images.Processing.set_dominant_color_for_images()
    |> image_task_started(socket, gettext("Recalculating dominant colors in the background."))
  end

  defp image_task_started({:ok, _job}, socket, message) do
    send(self(), {:toast, message})
    {:noreply, assign_image_tasks(socket)}
  end

  defp image_task_started({:error, :already_running}, socket, _message) do
    send(self(), {:toast, gettext("This is already running.")})
    {:noreply, assign_image_tasks(socket)}
  end

  defp image_task_started({:error, _reason}, socket, _message) do
    send(self(), {:toast, gettext("The operation could not be completed. Check the application logs and try again.")})
    {:noreply, socket}
  end

  # In a test, the checks' tasks join the page's SQL sandbox (`Brando.Doctor.run/1`).
  defp sandbox_owner(socket) do
    if Application.get_env(Brando.otp_app(), :sql_sandbox, false), do: get_connect_info(socket, :user_agent)
  end

  # The checks query and read files, so they run beside the page rather than
  # holding up its first render
  defp start_system_check(socket) do
    prefix = Brando.Tenant.current_prefix()
    locale = Gettext.get_locale(Brando.Gettext)
    sandbox = socket.assigns.doctor_sandbox

    socket
    |> assign(system_check: nil, system_check_failed: false)
    |> start_async(:system_check, fn ->
      Brando.Doctor.run(mode: :admin, prefix: prefix, locale: locale, sandbox: sandbox)
    end)
  end

  defp assign_authorization_tools(socket, params) do
    user = socket.assigns.current_user
    scope = if params["scope"] == "installation", do: Scope.installation(user), else: Scope.current(user)
    allowed? = Configuration.allowed?(scope)

    socket
    |> assign(:configuration_scope, scope)
    |> assign(:configuration_scope_label, scope_label(scope, socket.assigns[:current_site]))
    |> assign(:authorization_tools?, allowed?)
    |> assign(:legacy_mode?, !Engine.enabled?())
    |> assign(:migration_report, nil)
    |> assign(:authorization_busy, nil)
    |> assign(:authorization_message, nil)
    |> assign(:authorization_error, nil)
    |> assign(:authorization_backfilled?, false)
    |> assign(:configuration_preview, nil)
    |> assign(:configuration_json, nil)
    |> assign(:configuration_download, nil)
    |> allow_upload(:authorization_config, accept: ~w(.json), max_entries: 1, max_file_size: Configuration.max_bytes())
  end

  defp authorization_event(event, _, socket) when event in ["report", "backfill"] do
    if socket.assigns.authorization_busy do
      {:noreply, socket}
    else
      scope = socket.assigns.configuration_scope

      {:noreply,
       socket
       |> assign(:authorization_busy, event)
       |> assign(:authorization_error, nil)
       |> assign(:authorization_message, nil)
       |> start_async(:authorization_migration, fn ->
         if event == "report", do: Configuration.report(scope), else: Configuration.backfill(scope)
       end)}
    end
  end

  defp authorization_event("export", _, socket) do
    case Configuration.export(socket.assigns.configuration_scope) do
      {:ok, json} ->
        {:noreply,
         socket
         |> assign(:configuration_download, "data:application/json;base64," <> Base.encode64(json))
         |> assign(:authorization_error, nil)}

      {:error, reason} ->
        authorization_error(socket, reason)
    end
  end

  defp authorization_event("validate", _, socket) do
    {:noreply,
     socket
     |> assign(:configuration_preview, nil)
     |> assign(:configuration_json, nil)
     |> assign(:authorization_error, nil)}
  end

  defp authorization_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :authorization_config, ref)}
  end

  defp authorization_event("preview", _, socket) do
    case uploaded_entries(socket, :authorization_config) do
      {[_], []} ->
        [json] =
          consume_uploaded_entries(socket, :authorization_config, fn %{path: path}, _ -> {:ok, File.read!(path)} end)

        case Configuration.preview(socket.assigns.configuration_scope, json) do
          {:ok, preview} ->
            {:noreply,
             socket
             |> assign(:configuration_json, json)
             |> assign(:configuration_preview, preview)
             |> assign(:authorization_error, nil)
             |> assign(:authorization_message, nil)}

          {:error, reason} ->
            authorization_error(socket, reason)
        end

      _ ->
        authorization_error(socket, {:invalid_config, gettext("Choose a JSON file and wait for the upload to finish.")})
    end
  end

  defp authorization_event("cancel_preview", _, socket) do
    {:noreply, socket |> assign(:configuration_preview, nil) |> assign(:configuration_json, nil)}
  end

  defp authorization_event("apply", _, %{assigns: %{configuration_preview: nil}} = socket), do: {:noreply, socket}

  defp authorization_event("apply", _, socket) do
    case Configuration.apply(
           socket.assigns.configuration_scope,
           socket.assigns.configuration_json,
           socket.assigns.configuration_preview.revision
         ) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:configuration_preview, nil)
         |> assign(:configuration_json, nil)
         |> assign(:configuration_download, nil)
         |> assign(:authorization_error, nil)
         |> assign(
           :authorization_message,
           gettext(
             "Configuration imported. %{created} groups created, %{updated} updated, %{unchanged} unchanged. Memberships preserved.",
             created: result.created,
             updated: result.updated,
             unchanged: result.unchanged
           )
         )}

      {:error, :stale} ->
        socket = socket |> assign(:configuration_preview, nil) |> assign(:configuration_json, nil)
        authorization_error(socket, :stale)

      {:error, reason} ->
        authorization_error(socket, reason)
    end
  end

  defp authorization_event(_, _, socket), do: {:noreply, socket}

  # A job that already ran (Oban's inline testing mode) has reported by now
  defp queued(%{state: state} = index) when state in [:idle, :done, :failed], do: %{index | state: :queued}
  defp queued(index), do: index

  def handle_info({:search_index, %{state: :done, done: count}}, socket) do
    send(
      self(),
      {:toast, ngettext("Search index rebuilt: %{count} entry.", "Search index rebuilt: %{count} entries.", count)}
    )

    {:noreply,
     assign(socket, :search_index, %{
       state: :done,
       done: count,
       total: count,
       count: Search.count(),
       rebuilt_at: Search.rebuilt_at()
     })}
  end

  def handle_info({:search_index, %{state: state, done: done, total: total}}, socket) do
    {:noreply, update(socket, :search_index, &%{&1 | state: state, done: done, total: total})}
  end

  def handle_info({:image_maintenance, %{state: state} = run}, socket) do
    socket = assign(socket, :image_run, run)
    {:noreply, if(state == :done, do: assign_image_tasks(socket), else: socket)}
  end

  def handle_async(:system_check, {:ok, results}, socket) do
    {:noreply, assign(socket, system_check: results, system_check_failed: false)}
  end

  def handle_async(:system_check, {:exit, _reason}, socket) do
    {:noreply, assign(socket, system_check: nil, system_check_failed: true)}
  end

  def handle_async(:authorization_migration, result, socket) do
    if Configuration.allowed?(socket.assigns.configuration_scope) do
      backfilled? = socket.assigns.authorization_busy == "backfill"
      socket = assign(socket, :authorization_busy, nil)

      case result do
        {:ok, {:ok, report}} ->
          {:noreply,
           socket
           |> assign(:migration_report, report)
           |> assign(:authorization_backfilled?, socket.assigns.authorization_backfilled? or backfilled?)
           |> assign(:configuration_download, nil)
           |> assign(
             :authorization_message,
             if(backfilled?,
               do:
                 gettext("Groups prepared. Existing permission edits and previously removed memberships were preserved."),
               else: gettext("Report ready. Review application rules before switching to groups.")
             )
           )}

        {:ok, {:error, reason}} ->
          authorization_error(socket, reason)

        {:exit, _} ->
          authorization_error(socket, :failed)
      end
    else
      {:noreply, redirect(socket, to: "/admin/access-denied")}
    end
  end

  defp authorization_error(socket, reason), do: {:noreply, assign(socket, :authorization_error, error_message(reason))}
  defp error_message({:invalid_config, message}), do: message

  defp error_message(:stale),
    do: gettext("Groups or memberships changed after this preview. Choose the file again to review the latest changes.")

  defp error_message(:forbidden), do: gettext("Only an active Superuser can use authorization tools.")

  defp error_message(:site_not_found),
    do: gettext("The configured site was not found. Check the site configuration before preparing groups.")

  defp error_message(_), do: gettext("The operation could not be completed. Check the application logs and try again.")
  defp scope_label(%{kind: :installation}, _), do: gettext("Entire installation")
  defp scope_label(%{kind: :standalone}, _), do: gettext("This workspace")
  defp scope_label(_, %{name: name}), do: name
  defp scope_label(_, _), do: gettext("Selected site")

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
end
