defmodule BrandoAdmin.Sites.UtilsLive do
  @moduledoc false
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  import Phoenix.Component

  alias Brando.Authorization.{Configuration, Engine, Scope}
  alias BrandoAdmin.Components.AuthorizationTools

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
       |> assign_authorization_tools(params)}
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

      <section class="utils-maintenance" aria-labelledby="maintenance-title">
        <div class="utils-section-heading">
          <div>
            <h2 id="maintenance-title">
              {gettext("Maintenance")}
            </h2>
          </div>
        </div>
        <div class="utils-maintenance-list">
          <article>
            <div>
              <h3>{gettext("Content identifiers")}</h3><p>
                {gettext("Update the identifiers used to reference content.")}
              </p>
            </div>
            <button type="button" class="utils-button" phx-click="sync_identifiers" phx-disable-with={gettext("Syncing…")}>{gettext(
              "Sync identifiers"
            )}</button>
          </article>
          <article>
            <div>
              <h3>{gettext("Sitemap")}</h3><p>
                {gettext("Regenerate the sitemap from published content.")}
              </p>
              <small :if={@sitemap_last_updated}>
                {gettext("Last generated: %{last_updated}",
                  last_updated: Calendar.strftime(@sitemap_last_updated, "%d %b %Y, %H:%M %Z")
                )}
              </small>
              <small :if={!@sitemap_last_updated} class="utils-empty-status">{gettext("Not generated")}</small>
            </div>
            <button type="button" class="utils-button" phx-click="generate_sitemap" phx-disable-with={gettext("Generating…")}>{gettext(
              "Generate sitemap"
            )}</button>
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

  def handle_event("sync_identifiers", _, socket) do
    Brando.Blueprint.Identifier.sync()
    send(self(), {:toast, gettext("Identifiers synced.")})

    {:noreply, socket}
  end

  def handle_event("generate_sitemap", _, socket) do
    Brando.Sitemap.generate_sitemap()
    send(self(), {:toast, gettext("Generated sitemap.")})

    {:noreply, assign_sitemap(socket)}
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
