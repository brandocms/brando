defmodule BrandoAdmin.Components.ImagePicker do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext
  use BrandoAdmin.Components.PickerHelpers

  alias BrandoAdmin.Components.Assets.FileBrowser
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Images.FolderBrowser
  alias Phoenix.LiveView.JS

  def mount(socket) do
    {:ok,
     socket
     |> assign_new(:z_index, fn -> 1100 end)
     |> assign_defaults()
     |> stream(:visible_images, [])}
  end

  def update(
        %{event: "open_block_upload_browser"} = assigns,
        socket
      ) do
    config_target = assigns[:config_target] || socket.assigns.config_target || "default"
    recent_folders = assigns[:recent_folders] || socket.assigns.recent_folders

    {:ok,
     socket
     |> assign(:picker_mode, :block_upload)
     |> assign(:pending_upload_name, assigns[:upload_name])
     |> assign(:pending_file_count, assigns[:file_count] || 0)
     |> assign(:new_folder, "")
     |> assign(:show_new_folder_form, false)
     |> assign(:upload_uploading, false)
     |> assign(:upload_progress, 0)
     |> assign(:upload_total_files, 0)
     |> assign(:upload_completed_files, 0)
     |> assign(:form_id, assigns[:form_id] || socket.assigns.form_id)
     |> assign(:upload_name, nil)
     |> assign(:drop_target, nil)
     |> assign(:recent_folders, recent_folders)
     |> assign(:config_target, config_target)
     |> assign_images()
     |> assign_folder_state(assigns[:initial_folder])}
  end

  def update(
        %{config_target: config_target, event_target: event_target, multi: multi, selected_images: selected_images} =
          params,
        socket
      ) do
    {:ok,
     socket
     |> assign(:picker_mode, :select)
     |> assign(:pending_upload_name, nil)
     |> assign(:pending_file_count, 0)
     |> assign(:new_folder, "")
     |> assign(:show_new_folder_form, false)
     |> assign(:upload_uploading, false)
     |> assign(:upload_progress, 0)
     |> assign(:upload_total_files, 0)
     |> assign(:upload_completed_files, 0)
     |> assign(:form_id, params[:form_id] || socket.assigns.form_id)
     |> assign(:upload_name, params[:upload_name] || socket.assigns.upload_name)
     |> assign(:drop_target, params[:drop_target] || socket.assigns.drop_target)
     |> assign(:config_target, config_target)
     |> assign(:event_target, event_target)
     |> assign(:multi, multi)
     |> assign(:selected_images, selected_images)
     |> assign_images()
     |> assign_folder_state(nil)
     |> sync_picker_upload_folder()
     |> push_selection_state()}
  end

  def update(%{selected_images: selected_images}, socket) do
    {:ok,
     socket
     |> assign(:selected_images, selected_images)
     |> push_selection_state()}
  end

  def update(%{event: "picker_upload_progress"} = assigns, socket) do
    incoming_upload_name = normalize_upload_name(assigns[:upload_name])
    current_upload_name = normalize_upload_name(socket.assigns.upload_name)

    socket =
      if is_nil(current_upload_name) or current_upload_name == incoming_upload_name do
        upload_progress = Map.get(assigns, :upload_progress, socket.assigns.upload_progress || 0)

        if (socket.assigns.upload_total_files || 0) > 0 do
          assign(socket, :upload_progress, upload_progress)
        else
          socket
          |> assign(:upload_uploading, Map.get(assigns, :upload_uploading, false))
          |> assign(:upload_progress, upload_progress)
        end
      else
        socket
      end

    {:ok, socket}
  end

  def update(%{refresh_images: true} = assigns, socket) do
    requested_folder = Map.get(assigns, :requested_folder)

    {:ok,
     socket
     |> assign_defaults()
     |> assign_images()
     |> assign_folder_state(requested_folder || socket.assigns.current_folder)
     |> sync_picker_upload_folder()
     |> push_selection_state()}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign_defaults()
     |> assign(assigns)}
  end

  def assign_images(socket) do
    config_target = resolve_config_target(socket.assigns.config_target)

    {:ok, images} =
      Brando.Images.list_images(%{
        select: [:id, :width, :height, :formats, :status, :path, :sizes, :cdn, :config_target, :folder_id, :focal],
        filter: %{config_target: config_target, status: :processed},
        order: "desc id"
      })

    socket
    |> assign(:config_target, config_target)
    |> assign(:images, images)
  end

  # Resolve the config_target to the actual target used when storing images.
  # For example, "ref:gallery" has no registered config, so images are stored
  # with config_target "default". We need to query with the resolved target.
  defp resolve_config_target(nil), do: "default"

  defp resolve_config_target(config_target) do
    case Brando.Images.get_config_for(config_target) do
      {:ok, _} -> config_target
      _ -> "default"
    end
  rescue
    _ -> "default"
  end

  def handle_event("confirm_block_upload_folder", _, socket) do
    upload_name = socket.assigns.pending_upload_name
    absolute_folder = FolderBrowser.absolute_folder(socket.assigns.current_folder, socket.assigns.upload_root)
    folder_id = FolderBrowser.folder_id_for(socket.assigns.current_folder, socket.assigns.upload_root)
    config_target = socket.assigns.config_target || "default"

    if socket.assigns.form_id && upload_name do
      send_update(BrandoAdmin.Components.Form,
        id: socket.assigns.form_id,
        event: "set_block_upload_folder",
        upload_name: upload_name,
        folder: absolute_folder,
        folder_id: folder_id,
        config_target: config_target
      )
    end

    {:noreply,
     socket
     |> remember_folder(absolute_folder)
     |> push_event("b:block_upload_folder_confirmed", %{
       upload_name: to_string(upload_name),
       folder: absolute_folder,
       folder_id: folder_id
     })}
  end

  def handle_event("prepare_picker_upload", _, socket) do
    absolute_folder = FolderBrowser.absolute_folder(socket.assigns.current_folder, socket.assigns.upload_root)

    {:noreply,
     socket
     |> remember_folder(absolute_folder)
     |> sync_picker_upload_folder()}
  end

  def handle_event("picker_upload_started", %{"upload_name" => upload_name} = params, socket) do
    if normalize_upload_name(upload_name) == normalize_upload_name(socket.assigns.upload_name) do
      total_files = parse_nonnegative_int(Map.get(params, "total_files"), socket.assigns.upload_total_files || 1)
      completed_files = parse_nonnegative_int(Map.get(params, "completed_files"), 0)
      normalized_total = max(1, total_files)
      normalized_completed = min(completed_files, normalized_total)

      {:noreply,
       socket
       |> assign(:upload_uploading, true)
       |> assign(:upload_total_files, normalized_total)
       |> assign(:upload_completed_files, normalized_completed)
       |> assign(:upload_progress, 0)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("picker_upload_file_complete", %{"upload_name" => upload_name} = params, socket) do
    if normalize_upload_name(upload_name) == normalize_upload_name(socket.assigns.upload_name) do
      total_files =
        parse_nonnegative_int(
          Map.get(params, "total_files"),
          max(1, socket.assigns.upload_total_files || 1)
        )

      completed_files =
        parse_nonnegative_int(
          Map.get(params, "completed_files"),
          (socket.assigns.upload_completed_files || 0) + 1
        )

      {:noreply,
       socket
       |> assign(:upload_total_files, total_files)
       |> assign(:upload_completed_files, min(completed_files, total_files))
       |> assign(:upload_progress, 100)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("picker_upload_finished", %{"upload_name" => upload_name} = params, socket) do
    if normalize_upload_name(upload_name) == normalize_upload_name(socket.assigns.upload_name) do
      total_files =
        parse_nonnegative_int(
          Map.get(params, "total_files"),
          max(1, socket.assigns.upload_total_files || 1)
        )

      completed_files =
        parse_nonnegative_int(
          Map.get(params, "completed_files"),
          total_files
        )

      {:noreply,
       socket
       |> assign(:upload_uploading, false)
       |> assign(:upload_total_files, total_files)
       |> assign(:upload_completed_files, min(completed_files, total_files))
       |> assign(:upload_progress, 100)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("edit_image_from_picker", %{"id" => id}, socket) do
    with {:ok, image_id} <- parse_item_id(id),
         {:ok, image} <- Brando.Images.get_image(image_id) do
      if socket.assigns.form_id do
        send_update(Form,
          id: socket.assigns.form_id,
          action: :open_image_editor_from_picker,
          image: image
        )
      end
    end

    {:noreply, socket}
  end

  def handle_event("delete_image_from_picker", %{"id" => id}, socket) do
    with {:ok, image_id} <- parse_item_id(id) do
      _ = Brando.Images.delete_images([image_id])

      send(self(), {:toast, gettext("Image deleted")})

      {:noreply,
       socket
       |> assign(:selected_images, Enum.reject(socket.assigns.selected_images, &same_item_id?(&1, image_id)))
       |> assign_images()
       |> assign_folder_state(socket.assigns.current_folder)
       |> sync_picker_upload_folder()
       |> push_selection_state()}
    else
      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("organize_select_image", %{"id" => id} = params, socket) do
    with {:ok, parsed_id} <- parse_item_id(id) do
      meta? = truthy?(params["meta"])

      socket =
        if meta?,
          do: organize_select_range(socket, parsed_id),
          else: organize_select_toggle(socket, parsed_id)

      {:noreply, push_selection_state(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("clear_organize_selection", _, socket) do
    {:noreply,
     socket
     |> assign(:organize_selected, [])
     |> assign(:last_organize_selected_id, nil)
     |> push_selection_state()}
  end

  def handle_event("picker_move_to_folder", %{"folder" => folder, "ids" => ids}, socket) do
    ids = parse_selected_ids(ids)
    absolute_folder = FolderBrowser.absolute_folder(folder, socket.assigns.upload_root)

    cond do
      ids == [] ->
        {:noreply, socket}

      not folder_under_root?(absolute_folder, socket.assigns.upload_root) ->
        {:noreply, socket}

      true ->
        folder_id = FolderBrowser.folder_id_for(folder, socket.assigns.upload_root)
        move_images_to_folder(ids, folder_id)

        send(self(), {:toast, gettext("Moved %{count} images", count: length(ids))})

        {:noreply,
         socket
         |> assign(:organize_selected, [])
         |> assign(:last_organize_selected_id, nil)
         |> assign_images()
         |> assign_folder_state(socket.assigns.current_folder)
         |> push_selection_state()}
    end
  end

  def render(assigns) do
    ~H"""
    <div>
      <Content.drawer id={@id} title={gettext("Select image")} close={toggle_drawer("##{@id}")} z={@z_index} wide light>
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
            <:top_lead :if={@picker_mode == :block_upload}>
              <div class="image-picker-upload-callout">
                <div>
                  {gettext(
                    "Upload %{count} file(s) to this folder",
                    count: @pending_file_count
                  )}
                </div>
                <button
                  class="primary small"
                  type="button"
                  phx-click={JS.push("confirm_block_upload_folder", target: @myself) |> toggle_drawer("#image-picker")}
                >
                  {gettext("Upload here")}
                </button>
              </div>
            </:top_lead>
            <:toolbar_actions>
              <div class="image-picker-view-toggle">
                <button
                  id={"#{@id}-view-grid"}
                  class="view-toggle"
                  type="button"
                  phx-click={show_grid(@id)}
                >
                  {gettext("Grid")}
                </button>
                <button
                  id={"#{@id}-view-list"}
                  class="view-toggle is-active"
                  type="button"
                  phx-click={show_list(@id)}
                >
                  {gettext("List")}
                </button>
              </div>
            </:toolbar_actions>
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
          main_id={"image-picker-main-#{@id}"}
          enable_folder_drop={@picker_mode == :select}
          folder_drop_event="picker_move_to_folder"
        >
          <:main_header>
            <div class="image-picker-main-header">
              <h3>{folder_label_for_display(@current_folder, @upload_root)}</h3>
              <div class="image-picker-main-actions">
                <span>
                  {ngettext("%{count} image", "%{count} images", @image_count, count: @image_count)}
                </span>

                <div
                  :if={@upload_uploading}
                  class="picker-upload-progress"
                  role="status"
                  aria-live="polite"
                  data-label-current-file={gettext("Current file")}
                >
                  <span class="picker-upload-count">
                    {gettext("Uploaded %{uploaded}/%{total}",
                      uploaded: @upload_completed_files,
                      total: @upload_total_files
                    )}
                  </span>
                  <span class="picker-upload-current">{gettext("Current file")} {@upload_progress}%</span>
                  <progress value={@upload_progress} max="100">{@upload_progress}%</progress>
                </div>

                <button
                  :if={@picker_mode == :select && @upload_name}
                  type="button"
                  class="folder-action"
                  phx-click={
                    JS.push("prepare_picker_upload", target: @myself)
                    |> dispatch_upload_click(@upload_name, @drop_target)
                  }
                >
                  {gettext("Upload")}
                </button>
              </div>
            </div>
          </:main_header>

          <div
            id={"image-picker-drawer-#{@id}"}
            class="image-picker list"
            phx-hook="Brando.QueuedUploader"
            data-upload-target={if @picker_mode == :select && @upload_name, do: to_string(@upload_name), else: ""}
            data-upload-form="#image-drawer-form"
            data-progress-target={if @picker_mode == :select && @upload_name, do: "#image-picker-main-#{@id}", else: ""}
            data-progress-listener="true"
            data-listen-document-change={if @picker_mode == :select && @upload_name, do: "true", else: "false"}
            data-enable-drop={if @picker_mode == :select && @upload_name, do: "true", else: "false"}
            data-max-concurrency="1"
          >
            <div :if={@picker_mode == :select && @upload_name} class="folder-drop-indicator">
              <.icon name="hero-photo" />
              <span>{gettext("Drop files to upload into")}</span>
              <strong>{folder_label_for_display(@current_folder, @upload_root)}</strong>
            </div>

            <%= if @image_count == 0 do %>
              <div class="image-picker-empty">
                <button
                  :if={@picker_mode == :select && @upload_name}
                  type="button"
                  class="empty-upload-trigger"
                  phx-click={
                    JS.push("prepare_picker_upload", target: @myself)
                    |> dispatch_upload_click(@upload_name, @drop_target)
                  }
                >
                  <.icon name="hero-photo" />
                </button>
                <.icon :if={!(@picker_mode == :select && @upload_name)} name="hero-photo" />
                <h4>{gettext("No images in this folder")}</h4>
                <p>{gettext("Upload files here or choose another folder")}</p>
              </div>
            <% end %>

            <div
              :if={@organize_selected != []}
              class="image-picker-organize-bar"
            >
              <.icon name="hero-arrows-pointing-out" />
              <span>
                {ngettext(
                  "%{count} image selected for organizing",
                  "%{count} images selected for organizing",
                  length(@organize_selected),
                  count: length(@organize_selected)
                )}
              </span>
              <span class="image-picker-organize-hint">{gettext("Drag to a folder")}</span>
              <button
                type="button"
                class="image-picker-organize-clear"
                phx-click="clear_organize_selection"
                phx-target={@myself}
              >
                {gettext("Clear")}
              </button>
            </div>

            <div
              id={"image-picker-grid-#{@id}"}
              phx-update="stream"
              phx-hook="Brando.ImagePickerGrid"
              data-target-component={@myself}
            >
              <.image_row
                :for={{dom_id, image} <- @streams.visible_images}
                id={dom_id}
                image={image}
                multi={@multi}
                event_target={@event_target}
                picker_mode={@picker_mode}
                myself={@myself}
              />
            </div>
          </div>
        </.live_component>
      </Content.drawer>
    </div>
    """
  end

  def show_grid(js \\ %JS{}, id) do
    js
    |> JS.add_class("grid", to: "#image-picker-drawer-#{id}")
    |> JS.remove_class("list", to: "#image-picker-drawer-#{id}")
    |> JS.add_class("is-active", to: "##{id}-view-grid")
    |> JS.remove_class("is-active", to: "##{id}-view-list")
  end

  def show_list(js \\ %JS{}, id) do
    js
    |> JS.add_class("list", to: "#image-picker-drawer-#{id}")
    |> JS.remove_class("grid", to: "#image-picker-drawer-#{id}")
    |> JS.add_class("is-active", to: "##{id}-view-list")
    |> JS.remove_class("is-active", to: "##{id}-view-grid")
  end

  defp image_row(assigns) do
    menu_id = image_menu_id(assigns.image.id)
    assigns = assign(assigns, :menu_id, menu_id)

    ~H"""
    <div
      id={@id}
      class="image-picker__image"
      data-id={@image.id}
      phx-click={
        if @multi,
          do: JS.push("select_image", target: @event_target),
          else: JS.push("select_image", target: @event_target) |> toggle_drawer("#image-picker")
      }
      phx-value-id={@image.id}
    >
      <Content.image image={@image} size={:smallest} />
      <span class="image-picker__selected-indicator">
        <.icon name="hero-check-mini" />
      </span>
      <div class="image-picker__info">
        <div class="image-picker__name">
          <div class="image-picker__filename">{image_filename(@image.path)}</div>
          <div class="image-picker__dir">{image_directory(@image.path)}</div>
        </div>
        <div class="image-picker__meta">{@image.width}&times;{@image.height}</div>
        <div class="image-picker__meta">{image_formats(@image.formats)}</div>
        <div class="image-picker__status">{image_status(@image.status)}</div>
        <div :if={@picker_mode == :select} class="image-picker__actions">
          <button
            type="button"
            class="image-picker-action-button"
            aria-label={gettext("Image actions")}
            phx-click={toggle_dropdown("##{@menu_id}")}
            phx-click-away={hide_dropdown("##{@menu_id}")}
          >
            <.icon name="hero-ellipsis-horizontal-circle" />
          </button>
          <ul id={@menu_id} class="image-picker-action-dropdown hidden">
            <li>
              <button
                type="button"
                phx-click={
                  JS.push("edit_image_from_picker", target: @myself, value: %{id: @image.id})
                  |> hide_dropdown("##{@menu_id}")
                  |> toggle_drawer("#image-picker")
                  |> toggle_drawer("#image-editor-drawer")
                }
              >
                <.icon name="hero-pencil-square" />
                {gettext("Edit image")}
              </button>
            </li>
            <li>
              <button
                type="button"
                class="delete-action"
                phx-confirm={gettext("Delete this image?")}
                phx-click={
                  JS.push("delete_image_from_picker", target: @myself, value: %{id: @image.id})
                  |> hide_dropdown("##{@menu_id}")
                }
              >
                <.icon name="hero-trash" />
                {gettext("Delete image")}
              </button>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  defp assign_defaults(socket) do
    socket
    |> assign_new(:multi, fn -> false end)
    |> assign_new(:images, fn -> [] end)
    |> assign_new(:config_target, fn -> nil end)
    |> assign_new(:event_target, fn -> nil end)
    |> assign_new(:selected_images, fn -> [] end)
    |> assign_new(:picker_mode, fn -> :select end)
    |> assign_new(:pending_upload_name, fn -> nil end)
    |> assign_new(:pending_file_count, fn -> 0 end)
    |> assign_new(:form_id, fn -> nil end)
    |> assign_new(:upload_name, fn -> nil end)
    |> assign_new(:drop_target, fn -> nil end)
    |> assign_new(:folders, fn -> [""] end)
    |> assign_new(:custom_folders, fn -> [] end)
    |> assign_new(:child_folders, fn -> [] end)
    |> assign_new(:breadcrumbs, fn -> [%{label: "Root", folder: ""}] end)
    |> assign_new(:current_folder, fn -> "" end)
    |> assign_new(:new_folder, fn -> "" end)
    |> assign_new(:show_new_folder_form, fn -> false end)
    |> assign_new(:upload_root, fn -> "images/default" end)
    |> assign_new(:recent_folders, fn -> [] end)
    |> assign_new(:recent_folders_for_root, fn -> [] end)
    |> assign_new(:upload_uploading, fn -> false end)
    |> assign_new(:upload_progress, fn -> 0 end)
    |> assign_new(:upload_total_files, fn -> 0 end)
    |> assign_new(:upload_completed_files, fn -> 0 end)
    |> assign_new(:organize_selected, fn -> [] end)
    |> assign_new(:last_organize_selected_id, fn -> nil end)
    |> assign_new(:image_count, fn -> 0 end)
    |> assign_new(:visible_item_ids, fn -> [] end)
  end

  defp assign_folder_state(socket, requested_folder) do
    upload_root = FolderBrowser.upload_root(socket.assigns.config_target)

    folders =
      FolderBrowser.folders_from_entries(socket.assigns.images, upload_root)
      |> Kernel.++(socket.assigns.custom_folders)
      |> Enum.map(&(FolderBrowser.normalize_folder(&1) || ""))
      |> Enum.uniq()
      |> Enum.sort()

    requested_relative =
      case requested_folder do
        nil ->
          socket.assigns.current_folder

        folder ->
          FolderBrowser.relative_folder(folder, upload_root)
      end

    current_folder =
      if requested_relative in folders do
        requested_relative
      else
        ""
      end

    visible_images =
      FolderBrowser.entries_in_folder(
        socket.assigns.images,
        current_folder,
        upload_root
      )

    child_folders = FolderBrowser.child_folders(folders, current_folder)
    breadcrumbs = FolderBrowser.breadcrumbs(current_folder)

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
    |> assign(:image_count, length(visible_images))
    |> assign(:visible_item_ids, Enum.map(visible_images, & &1.id))
    |> stream(:visible_images, visible_images, reset: true)
    |> assign(:child_folders, child_folders)
    |> assign(:breadcrumbs, breadcrumbs)
    |> assign(:recent_folders_for_root, recent_folders_for_root)
  end

  # -- PickerHelpers callbacks --

  defp on_folder_change(socket) do
    socket
    |> sync_picker_upload_folder()
    |> push_selection_state()
  end

  defp push_selection_state(socket) do
    selected_ids = Enum.map(socket.assigns.selected_images, &normalize_item_id/1)
    organize_ids = socket.assigns.organize_selected

    push_event(socket, "image_picker_selection_changed", %{
      selected_ids: selected_ids,
      organize_ids: organize_ids
    })
  end

  # -- ImagePicker-specific helpers --

  defp image_filename(path) when is_binary(path), do: Path.basename(path)
  defp image_filename(_path), do: "-"

  defp image_directory(path) when is_binary(path) do
    case Path.dirname(path) do
      "." -> "Root"
      dir -> dir
    end
  end

  defp image_directory(_path), do: "Root"

  defp image_formats(formats) when is_list(formats) do
    case formats do
      [] ->
        "-"

      values ->
        Enum.map_join(values, ", ", &to_string/1)
    end
  end

  defp image_formats(_formats), do: "-"

  defp image_status(status) when is_atom(status) do
    status
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp image_status(status) when is_binary(status), do: status
  defp image_status(_status), do: "-"

  defp dispatch_upload_click(js, upload_name, drop_target) do
    selector =
      cond do
        is_binary(drop_target) and drop_target != "" -> "##{drop_target}"
        true -> ~s(#image-drawer-form input[name="#{upload_name}"])
      end

    JS.dispatch(js, "click", to: selector)
  end

  defp sync_picker_upload_folder(%{assigns: %{picker_mode: :select}} = socket) do
    upload_name = socket.assigns.upload_name
    form_id = socket.assigns.form_id
    current_folder = socket.assigns.current_folder
    upload_root = socket.assigns.upload_root

    folder = FolderBrowser.absolute_folder(current_folder, upload_root)
    folder_id = FolderBrowser.folder_id_for(current_folder, upload_root)

    if upload_name && form_id do
      send_update(Form,
        id: form_id,
        event: "set_block_upload_folder",
        upload_name: upload_name,
        folder: folder,
        folder_id: folder_id,
        config_target: socket.assigns.config_target || "default"
      )
    end

    socket
  end

  defp sync_picker_upload_folder(socket), do: socket

  defp image_menu_id(image_id), do: "image-picker-image-menu-#{image_id}"

  defp move_images_to_folder(ids, folder_id) when is_list(ids) do
    import Ecto.Query
    timestamp = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    from(i in Brando.Images.Image, where: i.id in ^ids)
    |> Brando.Repo.update_all(set: [folder_id: folder_id, updated_at: timestamp])
  end
end
