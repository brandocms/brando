defmodule BrandoAdmin.Components.ModuleFiles do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]
  alias Brando.Authorization.Boundary
  alias Brando.Content.{Definitions, Module}
  alias Brando.Content.Definition.{Archive, Plan}
  alias Brando.Repo
  alias BrandoAdmin.Components.Content
  alias Phoenix.LiveView.JS

  def mount(socket) do
    {:ok,
     socket
     |> assign(
       selected_ids: nil,
       download: nil,
       source: nil,
       filename: nil,
       mappings: "",
       plan: nil,
       result: nil,
       updated_download: nil,
       error: nil
     )
     |> allow_upload(:definition_zip, accept: ~w(.zip), max_entries: 1, max_file_size: Archive.max_bytes())}
  end

  def update(assigns, socket) do
    socket = assign(socket, Map.drop(assigns, [:selected_ids]))

    socket =
      if Map.has_key?(assigns, :selected_ids),
        do: assign(socket, selected_ids: assigns.selected_ids, download: nil),
        else: socket

    {:ok,
     assign(socket,
       can_export: BrandoAdmin.Authorization.allowed?(:export, Module),
       can_import:
         BrandoAdmin.Authorization.allowed?(:create, Module) || BrandoAdmin.Authorization.allowed?(:update, Module)
     )}
  end

  def render(assigns) do
    ~H"""
    <div id={@id}>
      <Content.modal
        id="module-files-modal"
        title={gettext("Import / export module files")}
        subtitle={@scope_label}
        icon="hero-arrow-path"
        wide
      >
        <div class="module-files">
          <div :if={@error} class="module-files-feedback error" role="alert">{@error}</div>
          <div :if={!@plan && !@result} class="module-files-grid">
            <section class="module-files-card module-files-export">
              <h3>{gettext("Export definitions")}</h3>
              <p>{gettext("Download editable DSL and template files, with a baseline for importing your changes back.")}</p>
              <p class="module-files-context">
                {if @selected_ids,
                  do: ngettext("%{count} selected module", "%{count} selected modules", length(@selected_ids)),
                  else: gettext("All local modules in this workspace")}
                <span>{gettext("Includes child modules and table templates.")}</span>
              </p>
              <div class="module-files-actions">
                <button
                  type="button"
                  class="module-files-button"
                  phx-click="export"
                  phx-target={@myself}
                  disabled={!@can_export}
                  phx-disable-with={gettext("Preparing…")}
                >{gettext("Prepare export")}</button>
                <a
                  :if={@download}
                  id="module-files-download"
                  class="module-files-button primary"
                  href={@download}
                  download="brando-modules.zip"
                >{gettext("Download ZIP")}</a>
              </div>
              <p :if={!@can_export}>{gettext("You do not have permission to export modules.")}</p>
            </section>
            <form
              id="module-files-import-form"
              class="module-files-card module-files-import"
              phx-change="validate"
              phx-submit="preview"
              phx-target={@myself}
              phx-auto-recover="ignore"
            >
              <h3>{gettext("Import definitions")}</h3>
              <p>{gettext("Upload a ZIP to review changes before updating existing modules or creating new ones.")}</p>
              <div class="module-files-dropzone" phx-drop-target={@uploads.definition_zip.ref}>
                <label for={@uploads.definition_zip.ref}>{gettext("Module definitions ZIP")}</label>
                <.live_file_input upload={@uploads.definition_zip} disabled={!@can_import} />
                <span>{gettext("Choose a file or drop it here · up to 5 MB")}</span>
              </div>
              <div :for={entry <- @uploads.definition_zip.entries} class="module-files-upload">
                <span>{entry.client_name}</span>
                <button
                  type="button"
                  class="module-files-button"
                  phx-click="cancel_upload"
                  phx-target={@myself}
                  phx-value-ref={entry.ref}
                >{gettext("Remove file")}</button>
                <progress value={entry.progress} max="100">{entry.progress}%</progress>
              </div>
              <p :for={error <- upload_errors(@uploads.definition_zip)} class="module-files-feedback error" role="alert">
                {upload_error(error)}
              </p>
              <p
                :for={error <- Enum.flat_map(@uploads.definition_zip.entries, &upload_errors(@uploads.definition_zip, &1))}
                class="module-files-feedback error"
                role="alert"
              >
                {upload_error(error)}
              </p>
              <div :if={@source} class="module-files-upload">
                <span>{@filename}</span>
                <button type="button" class="module-files-button" phx-click="reset" phx-target={@myself}>{gettext(
                  "Remove file"
                )}</button>
              </div>
              <details class="module-files-mappings" open={@mappings != ""}>
                <summary>{gettext("Destination reference mappings")}</summary>
                <div>
                  <p>
                    {gettext(
                      "For another installation or environment, map each external token to its destination record ID. Leave empty for the original workspace."
                    )}
                  </p>
                  <label for="module-files-mappings">{gettext("Reference mappings (JSON)")}</label>
                  <textarea id="module-files-mappings" name="references" rows="4" placeholder={~s({"cover": 42})}>{@mappings}</textarea>
                </div>
              </details>
              <div class="module-files-actions">
                <button
                  type="submit"
                  class="module-files-button primary"
                  phx-disable-with={gettext("Reading file…")}
                  disabled={!@can_import || (!@source && @uploads.definition_zip.entries == [])}
                >{gettext("Preview import")}</button>
              </div>
              <p :if={!@can_import}>{gettext("You do not have permission to import module definitions.")}</p>
            </form>
          </div>
          <section :if={@plan} id="module-files-preview" class="module-files-preview">
            <div class="module-files-preview-heading">
              <div>
                <h3 tabindex="-1" phx-mounted={JS.focus()}>{gettext("Review import")}</h3><p>{@filename}</p>
              </div>
              <span class="module-files-status">{gettext("Nothing has been applied")}</span>
            </div>
            <p>
              {gettext("Existing modules keep their identities. Editor content follows the normal synchronization rules.")}
            </p>
            <div class="module-files-counts">
              <span :for={{action, count} <- counts(@plan)} class={"module-files-badge #{action}"}>{action_label(action)}: {count}</span>
            </div>
            <div :if={!Plan.applicable?(@plan)} class="module-files-feedback error" role="alert">
              {gettext(
                "Resolve conflicts or required migrations before importing. Export the current definitions into a new bundle and reconcile your edits."
              )}
            </div>
            <p :if={@plan.items == []}>{gettext("This bundle contains no definitions.")}</p>
            <details
              :for={item <- @plan.items}
              class="module-files-change"
              open={item.action in [:conflict, :migration_required]}
            >
              <summary>
                <span><strong>{definition_name(@plan, item)}</strong><code>{item.uid}</code></span>
                <span class={"module-files-badge #{item.action}"}>{action_label(item.action)}</span>
              </summary>
              <div class="module-files-change-body">
                <p>
                  {gettext("%{blocks} blocks · %{entries} entries affected",
                    blocks: item.block_count,
                    entries: item.entry_count
                  )}
                </p>
                <p :if={item.reason}>{item.reason}</p>
                <p :if={item.diff == []}>{gettext("The definition is unchanged.")}</p>
                <section :for={change <- item.diff} class="module-files-diff">
                  <h4>{change.field}</h4>
                  <div>
                    <div><span>{gettext("Current")}</span><pre>{display_value(change.before)}</pre></div>
                    <div><span>{gettext("Imported")}</span><pre>{display_value(change.after)}</pre></div>
                  </div>
                </section>
              </div>
            </details>
          </section>
          <section :if={@result} id="module-files-result" class="module-files-result" role="status">
            <h3>{gettext("Import complete")}</h3>
            <p>{ngettext("%{count} definition changed.", "%{count} definitions changed.", length(@result.changes))}</p>
            <p>
              {gettext(
                "Download the updated bundle before making your next edit. It preserves your source files and records the new baseline."
              )}
            </p>
            <div class="module-files-actions">
              <a
                :if={@updated_download}
                id="module-files-updated-download"
                class="module-files-button primary"
                href={@updated_download}
                download="brando-modules-updated.zip"
              >{gettext("Download updated ZIP")}</a>
            </div>
            <div
              :for={refresh <- @result.refresh}
              class={["module-files-feedback", if(refresh.status == :failed, do: "error", else: "success")]}
            >
              <strong>{refresh.uid}</strong>
              <span :if={refresh.status == :failed}>{gettext("Definitions saved; refresh failed: %{reason}",
                reason: refresh.error
              )}</span>
              <span :if={refresh.status != :failed}>{gettext("Refresh requested · %{count} stale blocks remain",
                count: length(refresh.stale_block_ids)
              )}</span>
            </div>
            <button
              :if={@result.refresh != []}
              type="button"
              class="module-files-button"
              phx-click="refresh"
              phx-target={@myself}
              phx-disable-with={gettext("Retrying…")}
            >{gettext("Retry refresh")}</button>
          </section>
          <p class="module-files-note">
            {gettext(
              "DSL import updates the same module lineage. The existing copy/import tools remain available on the module list."
            )}
          </p>
        </div>
        <:footer :if={@plan || @result}>
          <div class="module-files-actions">
            <button :if={@plan || @result} type="button" class="module-files-button" phx-click="reset" phx-target={@myself}>
              {if @result, do: gettext("Back to import / export"), else: gettext("Cancel preview")}
            </button>
            <button
              :if={@plan}
              id="module-files-apply"
              type="button"
              class="module-files-button primary"
              phx-click="apply"
              phx-target={@myself}
              phx-disable-with={gettext("Applying…")}
              disabled={!Plan.applicable?(@plan) || @plan.items == []}
            >{gettext("Apply import")}</button>
          </div>
        </:footer>
      </Content.modal>
    </div>
    """
  end

  def handle_event("export", _, socket) do
    with {:ok, opts} <- export_options(socket.assigns.selected_ids),
         {:ok, exported} <- Archive.export(socket.assigns.current_user, opts) do
      {:noreply, assign(socket, download: data_url(exported.binary), error: nil)}
    else
      {:error, reason} -> error(socket, reason)
    end
  end

  def handle_event("validate", params, socket) do
    {:noreply, assign(socket, mappings: params["references"] || "", plan: nil, error: nil)}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, socket |> cancel_upload(:definition_zip, ref) |> assign(plan: nil, error: nil)}
  end

  def handle_event("preview", params, socket) do
    mappings = params["references"] || socket.assigns.mappings
    socket = assign(socket, mappings: mappings, plan: nil, error: nil)

    with :ok <- authorize_import(socket.assigns.current_user),
         {:ok, source, filename} <- source(socket) do
      socket = assign(socket, source: source, filename: filename)

      with {:ok, references} <- references(mappings),
           {:ok, plan} <- Definitions.plan(source.bundle, socket.assigns.current_user, references: references) do
        {:noreply, assign(socket, plan: plan)}
      else
        {:error, reason} -> error(socket, reason)
      end
    else
      {:error, reason} -> error(socket, reason)
    end
  end

  def handle_event("apply", _, %{assigns: %{plan: nil}} = socket), do: {:noreply, socket}

  def handle_event("apply", _, socket) do
    case Definitions.apply(socket.assigns.plan, socket.assigns.current_user) do
      {:ok, result} ->
        BrandoAdmin.LiveView.Listing.update_list_entries(Module)
        socket = assign(socket, plan: nil, result: result, error: nil, download: nil)

        case Archive.update(socket.assigns.source, result.bundle) do
          {:ok, binary} ->
            {:noreply, assign(socket, updated_download: data_url(binary))}

          {:error, _} ->
            error(
              socket,
              gettext(
                "Definitions were saved, but the updated ZIP could not be prepared. Export a fresh bundle before your next edit."
              )
            )
        end

      {:error, reason} ->
        error(assign(socket, plan: nil), reason)
    end
  end

  def handle_event("refresh", _, %{assigns: %{result: nil}} = socket), do: {:noreply, socket}

  def handle_event("refresh", _, socket) do
    uids = Enum.map(socket.assigns.result.refresh, & &1.uid)

    case Definitions.refresh(uids, socket.assigns.current_user) do
      {:ok, refresh} -> {:noreply, assign(socket, result: %{socket.assigns.result | refresh: refresh}, error: nil)}
      {:error, reason} -> error(socket, reason)
    end
  end

  def handle_event("reset", _, socket) do
    socket =
      Enum.reduce(socket.assigns.uploads.definition_zip.entries, socket, &cancel_upload(&2, :definition_zip, &1.ref))

    {:noreply,
     assign(socket, source: nil, filename: nil, mappings: "", plan: nil, result: nil, updated_download: nil, error: nil)}
  end

  defp source(socket) do
    case uploaded_entries(socket, :definition_zip) do
      {[_], []} ->
        [result] =
          consume_uploaded_entries(socket, :definition_zip, fn %{path: path}, entry ->
            {:ok, {Archive.read(File.read!(path)), entry.client_name}}
          end)

        case result do
          {{:ok, source}, name} -> {:ok, source, name}
          {{:error, reason}, _} -> {:error, reason}
        end

      {[], []} when not is_nil(socket.assigns.source) ->
        {:ok, socket.assigns.source, socket.assigns.filename}

      _ ->
        {:error, gettext("Choose a ZIP file and wait for the upload to finish.")}
    end
  end

  defp authorize_import(actor) do
    with {:ok, :ok} <- Definitions.protect(fn -> Definitions.validate_actor!(actor) end) do
      if Boundary.authorize(actor, :create, Module) == :ok || Boundary.authorize(actor, :update, Module) == :ok,
        do: :ok,
        else: {:error, :forbidden}
    end
  end

  defp export_options(nil), do: {:ok, []}

  defp export_options(ids) when is_list(ids) and ids != [] do
    uids = Repo.all(from(m in Module, where: m.id in ^ids and is_nil(m.deleted_at), select: m.uid))

    if length(uids) == length(ids),
      do: {:ok, [uids: uids]},
      else: {:error, gettext("A selected module is unavailable. Select the modules again.")}
  end

  defp export_options(_), do: {:error, gettext("Select at least one module to export.")}

  defp references(""), do: {:ok, %{}}

  defp references(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) ->
        if Enum.all?(map, fn {token, id} -> is_binary(token) && is_integer(id) && id > 0 end),
          do: {:ok, map},
          else: {:error, gettext("Reference mappings must map tokens to positive record IDs.")}

      _ ->
        {:error, gettext("Reference mappings must be a JSON object.")}
    end
  end

  defp error(socket, :forbidden), do: error(socket, gettext("You do not have permission for this action."))

  defp error(socket, reason),
    do: {:noreply, assign(socket, error: if(is_binary(reason), do: reason, else: inspect(reason)))}

  defp data_url(binary), do: "data:application/zip;base64," <> Base.encode64(binary)
  defp counts(plan), do: plan.items |> Enum.frequencies_by(& &1.action) |> Enum.sort()
  defp action_label(:create), do: gettext("Create")
  defp action_label(:noop), do: gettext("Unchanged")
  defp action_label(:update), do: gettext("Update")
  defp action_label(:conflict), do: gettext("Conflict")
  defp action_label(:migration_required), do: gettext("Migration required")
  defp display_value(nil), do: "—"
  defp display_value(value) when is_binary(value), do: value
  defp display_value(value), do: Jason.encode!(value, pretty: true)

  defp definition_name(plan, item) do
    definition = Enum.find(plan.bundle["modules"] ++ plan.bundle["table_templates"], &(&1["uid"] == item.uid))

    case definition["name"] do
      name when is_map(name) -> name[Gettext.get_locale(Brando.Gettext)] || name["en"] || item.uid
      name -> name
    end
  end

  defp upload_error(:too_large), do: gettext("The ZIP must be no larger than 5 MB.")
  defp upload_error(:too_many_files), do: gettext("Choose one ZIP file.")
  defp upload_error(:not_accepted), do: gettext("Choose a .zip file.")
  defp upload_error(_), do: gettext("The upload failed. Choose the file again.")
end
