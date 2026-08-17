defmodule BrandoAdmin.Components.ImagePicker do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext
  use BrandoAdmin.Components.PickerHelpers

  alias BrandoAdmin.Components.Assets.FileBrowser
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
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
     |> assign(:opened?, true)
     |> assign(:pending_upload_name, assigns[:upload_name])
     |> assign(:pending_file_count, assigns[:file_count] || 0)
     |> assign(:new_folder, "")
     |> assign(:show_new_folder_form, false)
     |> assign(:form_id, assigns[:form_id] || socket.assigns.form_id)
     |> assign(:recent_folders, recent_folders)
     |> assign(:config_target, config_target)
     |> assign_config_target()
     |> assign_folder_state(assigns[:initial_folder])
     # Show the drawer from HERE (not the Form handler) so the event rides the
     # same diff as this component's re-render — pushed from the Form it races
     # the picker's patch, which resets the class list and re-hides the drawer.
     |> push_event("b:show_drawer", %{drawer_id: "image-picker"})}
  end

  def update(
        %{config_target: config_target, event_target: event_target, multi: multi, selected_images: selected_images} =
          params,
        socket
      ) do
    {:ok,
     socket
     |> assign(:picker_mode, :select)
     |> assign(:opened?, true)
     |> assign(:pending_upload_name, nil)
     |> assign(:pending_file_count, 0)
     |> assign(:new_folder, "")
     |> assign(:show_new_folder_form, false)
     |> assign(:form_id, params[:form_id] || socket.assigns.form_id)
     |> assign(:config_target, config_target)
     |> assign(:event_target, event_target)
     |> assign(:multi, multi)
     |> assign(:selected_images, selected_images)
     |> assign_config_target()
     |> assign_folder_state(nil)
     |> push_selection_state()}
  end

  def update(%{selected_images: selected_images}, socket) do
    {:ok,
     socket
     |> assign(:selected_images, selected_images)
     |> push_selection_state()}
  end

  # Fired from `hooks.ex` on every `[:image, :updated]` — once per image during a
  # bulk upload, and `assign_folder_state/2` runs a full `list_images/1` each
  # time. A picker that has never been opened has nothing on screen to refresh,
  # and both open clauses call `assign_folder_state/2` themselves, so skipping
  # here cannot show stale data.
  #
  # This does NOT cover opened-then-closed: the drawer's closed state lives
  # entirely client-side (`b:show_drawer` has no server-side counterpart), so
  # knowing it would mean new client→server plumbing rather than a guard. N
  # uploads still cost N queries once the picker has been opened.
  def update(%{refresh_images: true} = assigns, socket) do
    socket = assign_defaults(socket)

    if socket.assigns.opened? do
      requested_folder = Map.get(assigns, :requested_folder)

      {:ok,
       socket
       |> assign_config_target()
       |> assign_folder_state(requested_folder || socket.assigns.current_folder)
       |> push_selection_state()}
    else
      {:ok, socket}
    end
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign_defaults()
     |> assign(assigns)}
  end

  # Resolves the config target only — it no longer assigns the library, hence
  # the name. The whole config-target library used to be RETAINED in
  # `socket.assigns.images`: one copy of every image row per connected admin,
  # for the life of the session, walked by LiveView change tracking on every
  # diff, when the only consumer is `assign_folder_state/2` and the rendered
  # list is already a stream.
  #
  # The tradeoff, stated plainly: folder navigation (`PickerHelpers` →
  # `assign_folder_state/2`) used to filter that cached list and now re-queries.
  # It is the same query the picker already runs on every open, and the five
  # other call sites re-queried anyway. What this does NOT do is bound the query
  # itself — see E6 in the form-audit plan for why per-folder scoping is a
  # bigger change: the folder tree is derived from the entries.
  #
  # (`VideoPicker`'s `:videos` assign looks identical but is NOT the same case —
  # there `assign_folder_state/2` is reached from a dozen places that do not
  # reload, so the assign is a real cache.)
  def assign_config_target(socket) do
    assign(socket, :config_target, resolve_config_target(socket.assigns.config_target))
  end

  defp list_images(config_target) do
    {:ok, images} =
      Brando.Images.list_images(%{
        select: [:id, :width, :height, :formats, :status, :path, :sizes, :cdn, :config_target, :folder_id, :focal],
        filter: %{config_target: config_target, status: :processed},
        order: "desc id"
      })

    images
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

    {:noreply,
     socket
     |> remember_folder(absolute_folder)
     |> push_event("b:block_upload_folder_confirmed", %{
       upload_name: to_string(upload_name),
       folder: absolute_folder,
       folder_id: folder_id
     })}
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
    case parse_item_id(id) do
      {:ok, image_id} ->
        _ = Brando.Images.delete_images([image_id])

        send(self(), {:toast, gettext("Image deleted")})

        {:noreply,
         socket
         |> assign(:selected_images, Enum.reject(socket.assigns.selected_images, &same_item_id?(&1, image_id)))
         |> assign_config_target()
         |> assign_folder_state(socket.assigns.current_folder)
         |> push_selection_state()}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("organize_select_image", %{"id" => id} = params, socket) do
    case parse_item_id(id) do
      {:ok, parsed_id} ->
        meta? = truthy?(params["meta"])

        socket =
          if meta?,
            do: organize_select_range(socket, parsed_id),
            else: organize_select_toggle(socket, parsed_id)

        {:noreply, push_selection_state(socket)}

      _ ->
        {:noreply, socket}
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
         |> assign_config_target()
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
              </div>
            </div>
          </:main_header>

          <div
            id={"image-picker-drawer-#{@id}"}
            class="image-picker list"
          >
            <%= if @image_count == 0 do %>
              <div class="image-picker-empty">
                <.icon name="hero-photo" />
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
      <span class="image-picker__selected-indicator" aria-hidden="true">
        <.icon name="hero-check-mini" />
      </span>
      <Content.image image={@image} size={:smallest} />
      <div class="image-picker__info">
        <div class="image-picker__name">
          <div class="image-picker__filename">{image_filename(@image.path)}</div>
          <div class="image-picker__dir">{image_directory(@image.path)}</div>
        </div>
        <div class="image-picker__meta">{@image.width}&times;{@image.height}</div>
        <div class="image-picker__meta">{image_formats(@image.formats)}</div>
        <div class="image-picker__status" data-status={@image.status}>{image_status(@image.status)}</div>
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
    |> assign_new(:config_target, fn -> nil end)
    |> assign_new(:event_target, fn -> nil end)
    |> assign_new(:selected_images, fn -> [] end)
    |> assign_new(:picker_mode, fn -> :select end)
    |> assign_new(:opened?, fn -> false end)
    |> assign_new(:pending_upload_name, fn -> nil end)
    |> assign_new(:pending_file_count, fn -> 0 end)
    |> assign_new(:form_id, fn -> nil end)
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
    |> assign_new(:organize_selected, fn -> [] end)
    |> assign_new(:last_organize_selected_id, fn -> nil end)
    |> assign_new(:image_count, fn -> 0 end)
    |> assign_new(:visible_item_ids, fn -> [] end)
  end

  defp assign_folder_state(socket, requested_folder) do
    upload_root = FolderBrowser.upload_root(socket.assigns.config_target)
    images = list_images(socket.assigns.config_target)

    folders =
      FolderBrowser.folders_from_entries(images, upload_root)
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

    visible_images = FolderBrowser.entries_in_folder(images, current_folder, upload_root)

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
    push_selection_state(socket)
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

  defp image_menu_id(image_id), do: "image-picker-image-menu-#{image_id}"

  defp move_images_to_folder(ids, folder_id) when is_list(ids) do
    import Ecto.Query
    timestamp = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    from(i in Brando.Images.Image, where: i.id in ^ids)
    |> Brando.Repo.update_all(set: [folder_id: folder_id, updated_at: timestamp])
  end
end
