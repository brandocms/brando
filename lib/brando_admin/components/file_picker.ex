defmodule BrandoAdmin.Components.FilePicker do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext
  use BrandoAdmin.Components.PickerHelpers

  alias Brando.Utils
  alias BrandoAdmin.Components.Assets.FileBrowser
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Images.FolderBrowser

  def mount(socket) do
    {:ok,
     socket
     |> assign_defaults()
     |> stream(:visible_files, [])}
  end

  def update(
        %{config_target: config_target, event_target: event_target, multi: multi, selected_files: selected_files},
        socket
      ) do
    {:ok,
     socket
     |> assign(:config_target, config_target)
     |> assign(:event_target, event_target)
     |> assign(:multi, multi)
     |> assign(:selected_files, selected_files)
     |> assign(:new_folder, "")
     |> assign(:show_new_folder_form, false)
     |> assign_files()
     |> assign_folder_state(nil)}
  end

  def update(%{selected_files: selected_files}, socket) do
    {:ok, assign(socket, :selected_files, selected_files)}
  end

  def update(%{refresh_files: true}, socket) do
    {:ok,
     socket
     |> assign_defaults()
     |> assign_files()
     |> assign_folder_state(socket.assigns.current_folder)}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign_defaults()
     |> assign(assigns)}
  end

  defp assign_defaults(socket) do
    socket
    |> assign_new(:multi, fn -> false end)
    |> assign_new(:files, fn -> [] end)
    |> assign_new(:config_target, fn -> nil end)
    |> assign_new(:event_target, fn -> nil end)
    |> assign_new(:z_index, fn -> 1100 end)
    |> assign_new(:selected_files, fn -> [] end)
    |> assign_new(:folders, fn -> [""] end)
    |> assign_new(:custom_folders, fn -> [] end)
    |> assign_new(:child_folders, fn -> [] end)
    |> assign_new(:breadcrumbs, fn -> [%{label: "Root", folder: ""}] end)
    |> assign_new(:current_folder, fn -> "" end)
    |> assign_new(:new_folder, fn -> "" end)
    |> assign_new(:show_new_folder_form, fn -> false end)
    |> assign_new(:upload_root, fn -> "files/default" end)
    |> assign_new(:recent_folders, fn -> [] end)
    |> assign_new(:recent_folders_for_root, fn -> [] end)
    |> assign_new(:organize_selected, fn -> [] end)
    |> assign_new(:last_organize_selected_id, fn -> nil end)
    |> assign_new(:visible_item_ids, fn -> [] end)
    |> assign_new(:file_count, fn -> 0 end)
  end

  defp assign_files(socket) do
    {:ok, files} =
      Brando.Files.list_files(%{
        select: [:id, :filename, :cdn, :config_target, :filesize, :folder_id],
        filter: %{config_target: socket.assigns.config_target},
        order: "desc id"
      })

    assign(socket, :files, files)
  end

  # -- PickerHelpers callbacks --

  defp on_folder_change(socket), do: socket

  defp assign_folder_state(socket, requested_folder) do
    upload_root = file_upload_root(socket.assigns.config_target)
    entries = Enum.map(socket.assigns.files, &%{id: &1.id, folder_id: &1.folder_id, path: nil})

    folders =
      entries
      |> FolderBrowser.folders_from_entries(upload_root)
      |> Kernel.++(socket.assigns.custom_folders)
      |> Enum.map(&(FolderBrowser.normalize_folder(&1) || ""))
      |> Enum.uniq()
      |> Enum.sort()

    requested_relative =
      case requested_folder do
        nil -> socket.assigns.current_folder
        folder -> FolderBrowser.relative_folder(folder, upload_root)
      end

    current_folder = if requested_relative in folders, do: requested_relative, else: ""

    matched_ids =
      entries
      |> FolderBrowser.entries_in_folder(current_folder, upload_root)
      |> Enum.map(& &1.id)
      |> MapSet.new()

    # Pre-folder files have no folder_id. Treat them as belonging to this
    # target's root so migration to the browser does not make them disappear.
    unassigned_ids =
      if current_folder == "" do
        entries
        |> Enum.filter(&is_nil(&1.folder_id))
        |> Enum.map(& &1.id)
        |> MapSet.new()
      else
        MapSet.new()
      end

    visible_ids = MapSet.union(matched_ids, unassigned_ids)

    visible_files =
      socket.assigns.files
      |> Enum.filter(&(&1.id in visible_ids))
      |> Enum.sort_by(& &1.id, :desc)

    recent_folders_for_root =
      socket.assigns.recent_folders
      |> Enum.map(&FolderBrowser.normalize_folder/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&folder_under_root?(&1, upload_root))
      |> Enum.reject(&(FolderBrowser.relative_folder(&1, upload_root) == ""))
      |> Enum.take(5)

    socket
    |> assign(:upload_root, upload_root)
    |> assign(:folders, folders)
    |> assign(:current_folder, current_folder)
    |> assign(:file_count, length(visible_files))
    |> assign(:visible_item_ids, Enum.map(visible_files, & &1.id))
    |> stream(:visible_files, visible_files, reset: true)
    |> assign(:child_folders, FolderBrowser.child_folders(folders, current_folder))
    |> assign(:breadcrumbs, FolderBrowser.breadcrumbs(current_folder))
    |> assign(:recent_folders_for_root, recent_folders_for_root)
  end

  defp file_upload_root(config_target) do
    case Brando.Uploads.resolve_file_config(config_target) do
      {%{upload_path: upload_path}, _resolved_target} ->
        FolderBrowser.normalize_folder(upload_path) || "files/default"

      _ ->
        "files/default"
    end
  end

  def render(assigns) do
    ~H"""
    <div>
      <Content.drawer id={@id} title={gettext("Select file")} close={toggle_drawer("##{@id}")} z={@z_index} wide light>
        <:info>
          <.live_component
            module={FileBrowser}
            id={"#{@id}-top"}
            section={:top}
            mode={:drawer}
            target={@myself}
            upload_root={@upload_root}
            current_folder={@current_folder}
            breadcrumbs={@breadcrumbs}
            recent_folders={@recent_folders_for_root}
          >
            <:top_lead :if={@config_target}>
              <div class="mb-2">{gettext("Select a compatible file from the library")}</div>
            </:top_lead>
          </.live_component>
        </:info>

        <.live_component
          module={FileBrowser}
          id={"#{@id}-browser"}
          section={:browser}
          mode={:drawer}
          target={@myself}
          upload_root={@upload_root}
          current_folder={@current_folder}
          breadcrumbs={@breadcrumbs}
          recent_folders={@recent_folders_for_root}
          show_recent_folders={false}
          child_folders={@child_folders}
          show_new_folder_form={@show_new_folder_form}
          new_folder={@new_folder}
          main_id={"file-picker-main-#{@id}"}
        >
          <:main_header>
            <div class="image-picker-main-header">
              <h3>{folder_label_for_display(@current_folder, @upload_root)}</h3>
              <div class="image-picker-main-actions">
                <span>{ngettext("%{count} file", "%{count} files", @file_count, count: @file_count)}</span>
              </div>
            </div>
          </:main_header>

          <div class="file-picker list" id={"file-picker-drawer-#{@id}"}>
            <div :if={@file_count == 0} class="image-picker-empty">
              <.icon name="hero-document" />
              <h4>{gettext("No files in this folder")}</h4>
              <p>{gettext("Choose another folder or upload a file from its context")}</p>
            </div>

            <div id={"file-picker-grid-#{@id}"} phx-update="stream">
              <.file_row
                :for={{dom_id, file} <- @streams.visible_files}
                id={dom_id}
                file={file}
                selected={Enum.any?(@selected_files, &same_item_id?(&1, file.id))}
                multi={@multi}
                event_target={@event_target}
              />
            </div>
          </div>
        </.live_component>
      </Content.drawer>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :file, :map, required: true
  attr :selected, :boolean, default: false
  attr :multi, :boolean, default: false
  attr :event_target, :any, required: true

  defp file_row(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      class={["file-picker__file", @selected && "selected"]}
      phx-click={
        if @multi,
          do: JS.push("select_file", target: @event_target),
          else: JS.push("select_file", target: @event_target) |> toggle_drawer("#file-picker")
      }
      phx-value-id={@file.id}
      phx-value-selected={to_string(@selected)}
    >
      <div class="file-picker__info">
        <div class="file-picker__filename">#{@file.id} {Utils.file_url(@file)}</div>
        <div class="file-picker__size">({Brando.Utils.human_size(@file.filesize)})</div>
      </div>
    </button>
    """
  end
end
