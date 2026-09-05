defmodule BrandoAdmin.Files.FileListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Files.File
  use Gettext, backend: Brando.Gettext

  alias Brando.Files
  alias Brando.Files.File
  alias Brando.Uploads.AssetIntent
  alias BrandoAdmin.Components.Assets.FileBrowser
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Images.FolderBrowser
  alias BrandoAdmin.LiveView.AssetListHelpers
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    {:ok, default_cfg} = Files.get_config_for(%{config_target: "default"})
    upload_root = FolderBrowser.scope_for(default_cfg.upload_path)
    deliver_topic = "form:" <> Ecto.UUID.generate()
    if connected?(socket), do: Phoenix.PubSub.subscribe(Brando.pubsub(), deliver_topic)

    socket =
      socket
      |> allow_upload(:files,
        accept: :any,
        max_entries: 10,
        max_file_size: 50_000_000,
        auto_upload: true,
        progress: &handle_progress/3
      )
      |> assign(:recent_folders, [])
      |> assign(:deliver_topic, deliver_topic)
      |> assign(:replacement_file, nil)
      |> assign(:replacement_target, nil)
      |> assign(:custom_folders, [])
      |> assign(:folders, [""])
      |> assign(:child_folders, [])
      |> assign(:current_folder, "")
      |> assign(:current_folder_abs, nil)
      |> assign(:upload_root, upload_root)
      |> assign(:breadcrumbs, [%{label: "Root", folder: ""}])
      |> assign(:new_folder, "")
      |> assign(:show_new_folder_form, false)
      |> assign(:visible_file_count, 0)
      |> assign(:current_folder_config_target, "default")
      |> assign(:clipboard_ids, [])
      |> assign_folder_state(nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    folder_filter = params["filter:folder_id"] || params["filter:path"]
    {:noreply, assign_folder_state(socket, folder_filter)}
  end

  @impl true
  def handle_event("focus", _, socket), do: {:noreply, socket}
  def handle_event("blur", _, socket), do: {:noreply, socket}

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("replace_file", %{"id" => id}, socket) do
    with {:ok, %{deleted_at: nil} = file} <- Files.get_file(id),
         {:ok, target} <-
           AssetIntent.normalize(%{
             kind: "file_replace",
             asset_type: "file",
             file_id: file.id,
             config_target: file.config_target,
             deliver_topic: socket.assigns.deliver_topic
           }) do
      {:noreply, socket |> assign(:replacement_file, file) |> assign(:replacement_target, target)}
    else
      _ ->
        send(self(), {:toast, gettext("The file is no longer available")})
        {:noreply, socket}
    end
  end

  def handle_event("close_file_replacement", _, socket) do
    {:noreply, socket |> assign(:replacement_file, nil) |> assign(:replacement_target, nil)}
  end

  def handle_event("assets_go_root", _, socket) do
    {:noreply, AssetListHelpers.patch_folder_filter(socket, nil)}
  end

  def handle_event("assets_go_folder", %{"folder" => folder}, socket) do
    folder_id = FolderBrowser.folder_id_for(folder, socket.assigns.upload_root)
    {:noreply, AssetListHelpers.patch_folder_filter(socket, folder_id)}
  end

  def handle_event("assets_go_parent", _, socket) do
    {:noreply, AssetListHelpers.go_parent(socket)}
  end

  def handle_event("assets_go_recent", %{"folder" => folder}, socket) do
    relative = FolderBrowser.relative_folder(folder, socket.assigns.upload_root)
    folder_id = FolderBrowser.folder_id_for(relative, socket.assigns.upload_root)
    {:noreply, AssetListHelpers.patch_folder_filter(socket, folder_id)}
  end

  def handle_event("assets_show_new_folder_form", _, socket) do
    {:noreply, assign(socket, :show_new_folder_form, true)}
  end

  def handle_event("assets_cancel_new_folder_form", _, socket) do
    {:noreply,
     socket
     |> assign(:new_folder, "")
     |> assign(:show_new_folder_form, false)}
  end

  def handle_event("assets_create_folder", %{"folder" => %{"name" => folder_name}}, socket) do
    {:noreply, AssetListHelpers.create_folder(socket, folder_name)}
  end

  def handle_event("assets_move_selected_to_folder", %{"folder" => folder, "ids" => ids}, socket) do
    ids = AssetListHelpers.parse_selected_ids(ids)
    absolute_folder = FolderBrowser.absolute_folder(folder, socket.assigns.upload_root)

    cond do
      ids == [] ->
        {:noreply, socket}

      not AssetListHelpers.folder_under_root?(absolute_folder, socket.assigns.upload_root) ->
        {:noreply, socket}

      true ->
        folder_id = FolderBrowser.folder_id_for(folder, socket.assigns.upload_root)
        AssetListHelpers.move_entries_to_folder(File, ids, folder_id)
        AssetListHelpers.update_list_entries(socket.assigns.schema)

        send(self(), {:toast, gettext("Moved %{count} files", count: length(ids))})

        send_update(Content.List,
          id: AssetListHelpers.listing_id(socket.assigns.schema),
          action: :clear_selection
        )

        {:noreply, assign_folder_state(socket, socket.assigns.current_folder)}
    end
  end

  @impl true
  def handle_event("assets_cut_selected", %{"ids" => ids}, socket) do
    ids = AssetListHelpers.parse_selected_ids(ids)

    if ids == [] do
      {:noreply, socket}
    else
      send(self(), {:toast, gettext("Cut %{count} files", count: length(ids))})

      send_update(Content.List,
        id: AssetListHelpers.listing_id(socket.assigns.schema),
        action: :clear_selection
      )

      {:noreply, assign(socket, :clipboard_ids, ids)}
    end
  end

  @impl true
  def handle_event("assets_paste_selected", _, %{assigns: %{clipboard_ids: []}} = socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("assets_paste_selected", _, socket) do
    folder_id = FolderBrowser.folder_id_for(socket.assigns.current_folder, socket.assigns.upload_root)
    ids = socket.assigns.clipboard_ids

    AssetListHelpers.move_entries_to_folder(File, ids, folder_id)
    AssetListHelpers.update_list_entries(socket.assigns.schema)

    send(
      self(),
      {:toast,
       gettext("Moved %{count} files to %{folder}",
         count: length(ids),
         folder: folder_label_for_display(socket.assigns.current_folder_abs, socket.assigns.upload_root)
       )}
    )

    {:noreply,
     socket
     |> assign(:clipboard_ids, [])
     |> assign_folder_state(socket.assigns.current_folder)}
  end

  @impl true
  def handle_event("assets_clear_clipboard", _, socket) do
    {:noreply, assign(socket, :clipboard_ids, [])}
  end

  def handle_progress(:files, entry, socket) do
    if entry.done? do
      config_target = socket.assigns.current_folder_config_target || "default"
      {:ok, cfg} = Files.get_config_for(%{config_target: config_target})
      folder_id = FolderBrowser.folder_id_for(socket.assigns.current_folder, socket.assigns.upload_root)
      cfg = maybe_override_file_upload_path(cfg, socket.assigns.current_folder_abs)

      case consume_uploaded_entry(socket, entry, fn %{path: path} ->
             case Files.Uploads.Schema.handle_upload(
                    %{
                      "file" => %Plug.Upload{filename: entry.client_name, content_type: entry.client_type, path: path},
                      "config_target" => config_target,
                      "folder_id" => folder_id
                    },
                    cfg,
                    socket.assigns.current_user
                  ) do
               {:ok, file} -> {:ok, file}
               {:error, reason} -> {:ok, {:upload_error, reason}}
             end
           end) do
        {:upload_error, _reason} ->
          send(self(), {:toast, gettext("Failed to upload file")})

        _file ->
          send(self(), {:toast, gettext("File uploaded successfully")})
          AssetListHelpers.update_list_entries(socket.assigns.schema)
      end
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:asset_ready, %{"kind" => "file_replace"}, file}, socket) do
    AssetListHelpers.update_list_entries(socket.assigns.schema)
    send(self(), {:toast, gettext("File replaced")})

    socket =
      if socket.assigns.replacement_file && socket.assigns.replacement_file.id == file.id do
        socket |> assign(:replacement_file, nil) |> assign(:replacement_target, nil)
      else
        socket
      end

    {:noreply, assign_folder_state(socket, socket.assigns.current_folder)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Content.header title={gettext("Assets — Files")} subtitle={gettext("Overview")} />

    <Content.modal
      :if={@replacement_file}
      id="file-replacement-modal"
      title={gettext("Replace file")}
      show
      medium
      close={JS.push("close_file_replacement")}
    >
      <p>{gettext("Replace this file everywhere it is used. Its filename and URL will stay the same.")}</p>
      <div class="field-wrapper">
        <label for="replacement-filename">{gettext("Current file")}</label>
        <input id="replacement-filename" class="text" type="text" readonly value={@replacement_file.filename} />
      </div>
      <p class="monospace tiny">{Brando.Utils.media_url(@replacement_file)}</p>
      <p>{gettext("Choose a file with the same extension as the original.")}</p>
      <div
        id={"file-replacement-upload-#{@replacement_file.id}"}
        phx-hook="Brando.UploadTrigger"
        data-kind={@replacement_target["kind"]}
        data-asset-type={@replacement_target["asset_type"]}
        data-file-id={@replacement_target["file_id"]}
        data-config-target={@replacement_target["config_target"]}
        data-deliver-topic={@replacement_target["deliver_topic"]}
        data-accept={Path.extname(@replacement_file.filename)}
        data-click-mode="trigger"
      >
        <input type="file" class="file-input hidden" aria-label={gettext("Replacement file")} />
        <button type="button" class="primary upload-trigger">{gettext("Choose replacement")}</button>
      </div>
      <:footer>
        <button type="button" class="secondary" phx-click="close_file_replacement">{gettext("Close")}</button>
      </:footer>
    </Content.modal>

    <.live_component
      module={FileBrowser}
      id="assets-file-browser"
      mode={:inline}
      upload_root={@upload_root}
      current_folder={@current_folder}
      breadcrumbs={@breadcrumbs}
      recent_folders={@recent_folders}
      child_folders={@child_folders}
      show_new_folder_form={@show_new_folder_form}
      new_folder={@new_folder}
      go_root_event="assets_go_root"
      go_folder_event="assets_go_folder"
      go_parent_event="assets_go_parent"
      go_recent_event="assets_go_recent"
      enable_folder_drop={true}
      folder_drop_event="assets_move_selected_to_folder"
      show_new_folder_event="assets_show_new_folder_form"
      cancel_new_folder_event="assets_cancel_new_folder_form"
      create_folder_event="assets_create_folder"
      main_id="assets-file-browser-main"
    >
      <:main_header>
        <div class="image-picker-main-header">
          <h3>{folder_label_for_display(@current_folder_abs, @upload_root)}</h3>
          <div class="image-picker-main-actions">
            <span>
              {ngettext("%{count} file", "%{count} files", @visible_file_count, count: @visible_file_count)}
            </span>
            <span :if={@clipboard_ids != []} class="clipboard-status">
              {gettext("Cut queue")}: {length(@clipboard_ids)}
            </span>
            <form phx-change="validate" phx-drop-target={@uploads.files.ref}>
              <label class="folder-action">
                <span>{gettext("Upload")}</span>
                <.live_file_input upload={@uploads.files} class="hidden" />
              </label>
            </form>
            <button
              :if={@clipboard_ids != []}
              type="button"
              class="folder-action"
              phx-click="assets_paste_selected"
            >
              {gettext("Paste")}
            </button>
            <button
              :if={@clipboard_ids != []}
              type="button"
              class="folder-action"
              phx-click="assets_clear_clipboard"
            >
              {gettext("Clear")}
            </button>
          </div>
        </div>
      </:main_header>

      <.live_component
        module={Content.List}
        id={"content_listing_#{@schema}_default"}
        schema={@schema}
        current_user={@current_user}
        uri={@uri}
        params={AssetListHelpers.list_params(@params)}
        listing={:default}
        extra_selection_actions={[
          %{event: "assets_cut_selected", label: gettext("Cut selected")}
        ]}
      />
    </.live_component>
    """
  end

  defp assign_folder_state(socket, folder_filter) do
    {:ok, files} = Files.list_files(%{select: [:filename, :folder_id, :config_target], order: "desc id"})

    folders =
      FolderBrowser.folders_from_entries(files, socket.assigns.upload_root)
      |> Kernel.++(socket.assigns.custom_folders)
      |> Enum.map(&(FolderBrowser.normalize_folder(&1) || ""))
      |> Enum.uniq()
      |> Enum.sort()

    current_folder = AssetListHelpers.resolve_current_folder(folder_filter, socket.assigns.upload_root)
    current_folder = if current_folder in folders, do: current_folder, else: ""

    current_folder_abs =
      if current_folder == "" do
        nil
      else
        FolderBrowser.absolute_folder(current_folder, socket.assigns.upload_root)
      end

    child_folders = FolderBrowser.child_folders(folders, current_folder)
    breadcrumbs = FolderBrowser.breadcrumbs(current_folder)
    visible_files = FolderBrowser.entries_in_folder(files, current_folder, socket.assigns.upload_root)

    current_folder_config_target =
      resolve_folder_config_target(files, visible_files, current_folder, current_folder_abs, socket.assigns.upload_root)

    recent_folders =
      if current_folder_abs do
        FolderBrowser.push_recent_folder(socket.assigns.recent_folders, current_folder_abs)
      else
        socket.assigns.recent_folders
      end

    socket
    |> assign(:folders, folders)
    |> assign(:child_folders, child_folders)
    |> assign(:current_folder, current_folder)
    |> assign(:current_folder_abs, current_folder_abs)
    |> assign(:breadcrumbs, breadcrumbs)
    |> assign(:recent_folders, recent_folders)
    |> assign(
      :visible_file_count,
      if(current_folder == "", do: Enum.count(files, &is_nil(&1.folder_id)), else: length(visible_files))
    )
    |> assign(:current_folder_config_target, current_folder_config_target)
  end

  defp maybe_override_file_upload_path(cfg, nil), do: cfg

  defp maybe_override_file_upload_path(%Brando.Type.FileConfig{} = cfg, folder) do
    resolved_folder = FolderBrowser.absolute_folder(folder, cfg.upload_path)

    if resolved_folder do
      %{cfg | upload_path: resolved_folder}
    else
      cfg
    end
  end

  defp maybe_override_file_upload_path(cfg, _folder), do: cfg

  defp folder_label_for_display(folder, upload_root) do
    case FolderBrowser.relative_folder(folder, upload_root) do
      "" -> "Root"
      value -> value
    end
  end

  defp resolve_folder_config_target(files, visible_files, current_folder, current_folder_abs, upload_root) do
    most_common_config_target(visible_files) ||
      resolve_config_target_from_folder_prefix(files, current_folder, current_folder_abs, upload_root) ||
      "default"
  end

  defp most_common_config_target(entries) do
    entries
    |> Enum.map(&normalize_config_target(&1.config_target))
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(%{}, fn config_target, acc ->
      Map.update(acc, config_target, 1, &(&1 + 1))
    end)
    |> case do
      counts when map_size(counts) == 0 ->
        nil

      counts ->
        counts
        |> Enum.max_by(fn {_config_target, count} -> count end)
        |> elem(0)
    end
  end

  defp resolve_config_target_from_folder_prefix(files, current_folder, current_folder_abs, upload_root) do
    folder_abs =
      FolderBrowser.normalize_folder(current_folder_abs) ||
        FolderBrowser.absolute_folder(current_folder, upload_root)

    root = FolderBrowser.normalize_folder(upload_root)

    cond do
      is_nil(folder_abs) or is_nil(root) ->
        nil

      folder_abs == root ->
        nil

      true ->
        files
        |> Enum.map(&normalize_config_target(&1.config_target))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> Enum.map(fn config_target ->
          {config_target, upload_path_for_config_target(config_target)}
        end)
        |> Enum.filter(fn {_config_target, upload_path} ->
          is_binary(upload_path) and
            (folder_abs == upload_path || String.starts_with?(folder_abs, upload_path <> "/"))
        end)
        |> Enum.sort_by(fn {_config_target, upload_path} -> String.length(upload_path) end, :desc)
        |> case do
          [{config_target, _upload_path} | _] -> config_target
          _ -> nil
        end
    end
  end

  defp upload_path_for_config_target(config_target) do
    case Files.get_config_for(%{config_target: config_target}) do
      {:ok, cfg} -> FolderBrowser.normalize_folder(cfg.upload_path)
      _ -> nil
    end
  end

  defp normalize_config_target(config_target) when is_binary(config_target) do
    normalized = String.trim(config_target)
    if normalized == "", do: nil, else: normalized
  end

  defp normalize_config_target(_), do: nil
end
