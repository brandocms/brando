defmodule BrandoAdmin.Components.ImagePicker do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext
  use BrandoAdmin.Components.PickerHelpers

  alias BrandoAdmin.Components.Assets.FileBrowser
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.PickerFolders
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
    # Each opening names its own target. Falling back to the previous one left
    # a block's upload scoped to whatever field opened the picker last.
    config_target = assigns[:config_target] || "default"
    recent_folders = assigns[:recent_folders] || socket.assigns.recent_folders

    {:ok,
     socket
     |> assign(:picker_mode, :block_upload)
     |> leave_library()
     |> assign(:opened?, true)
     |> assign(:pending_upload_name, assigns[:upload_name])
     |> assign(:pending_request_id, assigns[:request_id])
     |> assign(:pending_file_count, assigns[:file_count] || 0)
     |> assign(:pending_video_count, assigns[:video_count] || 0)
     |> assign(:pending_video_folder, assigns[:video_folder])
     |> assign(:pending_target_label, assigns[:target_label])
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
     |> leave_library()
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
    socket = assign(socket, :config_target, resolve_config_target(socket.assigns.config_target))
    assign(socket, :library_offered?, library_offered?(socket.assigns))
  end

  # The rest of the library is offered to a pick for one field, ref or var,
  # whose image config a picked image is copied into (`for_config_target/3`),
  # and only to an editor who may add images.
  defp library_offered?(%{picker_mode: :select, multi: false, config_target: target, current_user: user})
       when is_binary(target) and not is_nil(user),
       do: Brando.Authorization.Media.authorize(user, :image) == :ok

  defp library_offered?(_assigns), do: false

  # The image fields a picker row needs.
  @list_fields [:id, :width, :height, :formats, :status, :path, :sizes, :cdn, :config_target, :folder_id, :focal, :title]

  # What placing an image in a folder and searching it need. The whole
  # library is listed with these; rows are loaded a page at a time.
  @index_fields [:id, :path, :folder_id, :title]

  # Rows rendered at a time. The rest load as the list scrolls (or from the
  # "show more" button), so a big folder doesn't put 1000+ rows in the form.
  @page_size 100

  # `config_target: :all` browses the whole library from the images root, for
  # pickers that are not choosing for a field (the AI assistant's attachments).
  # `scope: :library` does the same for a field's pick, which copies an image
  # made for another config into the field's.
  defp list_images(config_target, scope) do
    # Browsing everything still leaves out hidden folders: media the site's
    # visitors sent is not the site's to pick from.
    filter =
      if config_target == :all or scope == :library,
        do: %{library: true},
        else: %{config_target: config_target}

    {:ok, images} =
      Brando.Images.list_images(%{
        select: @index_fields,
        filter: Map.put(filter, :status, :processed),
        order: "desc id"
      })

    images
  end

  # Resolve the config_target to the actual target used when storing images.
  # For example, "ref:gallery" has no registered config, so images are stored
  # with config_target "default". We need to query with the resolved target.
  defp resolve_config_target(nil), do: "default"
  defp resolve_config_target(:all), do: :all

  # Fields send `{"image", schema, field}` as well as the serialized string.
  defp resolve_config_target(config_target) do
    target = Brando.Assets.ConfigTarget.serialize(config_target)

    case Brando.Images.get_config_for(target) do
      {:ok, _} -> target
      _ -> "default"
    end
  rescue
    _ -> "default"
  end

  def handle_event("cancel_pending_upload", _, socket) do
    {:noreply,
     socket
     |> close_list()
     |> push_event("b:block_upload_folder_cancelled", %{
       upload_name: socket.assigns[:pending_upload_name],
       request_id: socket.assigns[:pending_request_id]
     })}
  end

  def handle_event("picker_closed", _, socket) do
    {:noreply, close_list(socket)}
  end

  # Opening again for the target it was last set up for — the image drawer's
  # "Select image". A closed picker has emptied its list (`close_list/1`), and
  # only the openings that send a new target load it again, so this one came
  # up blank.
  def handle_event("reopen", _, %{assigns: %{config_target: config_target}} = socket)
      when not is_nil(config_target) do
    {:noreply,
     socket
     |> assign(:opened?, true)
     |> assign_config_target()
     |> assign_folder_state(socket.assigns.current_folder)
     |> push_selection_state()}
  end

  def handle_event("reopen", _, socket), do: {:noreply, socket}

  def handle_event("set_scope", %{"scope" => scope}, socket) when scope in ["field", "library"] do
    if socket.assigns.library_offered? do
      {:noreply, socket |> switch_scope(String.to_existing_atom(scope), "") |> push_selection_state()}
    else
      {:noreply, socket}
    end
  end

  # Root and Up at the root of the field's own images lead on into the rest
  # of the library: to its root, or to the folder above the field's.
  def handle_event(
        "picker_go_root",
        _,
        %{assigns: %{scope: :field, library_offered?: true, current_folder: ""}} = socket
      ) do
    {:noreply, socket |> switch_scope(:library, "") |> push_selection_state()}
  end

  def handle_event("picker_go_root", params, socket), do: handle_event("go_root", params, socket)

  def handle_event(
        "picker_go_parent",
        _,
        %{assigns: %{scope: :field, library_offered?: true, current_folder: ""}} = socket
      ) do
    parent =
      socket.assigns.upload_root
      |> Path.dirname()
      |> FolderBrowser.relative_folder(picker_upload_root(:all))

    {:noreply, socket |> switch_scope(:library, parent) |> push_selection_state()}
  end

  def handle_event("picker_go_parent", params, socket), do: handle_event("go_parent_folder", params, socket)

  # A pick from the whole library: the image, or a copy of it cut to this
  # field's config, goes to the field through its own `select_image`
  # (`ImagePickerGrid` sends it on).
  def handle_event("pick_library_image", %{"id" => id}, %{assigns: %{library_offered?: true}} = socket) do
    case parse_item_id(id) do
      {:ok, image_id} -> {:noreply, start_pick(socket, image_id)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("pick_library_image", _, socket), do: {:noreply, socket}

  def handle_event("search_images", %{"search" => search}, socket) do
    {:noreply,
     socket
     |> assign(:search, String.trim(search))
     |> assign_folder_state(socket.assigns.current_folder)
     |> push_selection_state()}
  end

  def handle_event("load_more_images", _, socket) do
    {:noreply, socket |> stream_next_page() |> push_selection_state()}
  end

  def handle_event("confirm_block_upload_folder", _, socket) do
    upload_name = socket.assigns.pending_upload_name
    absolute_folder = FolderBrowser.absolute_folder(socket.assigns.current_folder, socket.assigns.upload_root)
    folder_id = FolderBrowser.folder_id_for(socket.assigns.current_folder, socket.assigns.upload_root)

    {:noreply,
     socket
     |> remember_folder(absolute_folder)
     |> close_list()
     |> push_event("b:block_upload_folder_confirmed", %{
       upload_name: to_string(upload_name),
       request_id: socket.assigns[:pending_request_id],
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

  def handle_async(:pick_library_image, {:ok, {:ok, picked}}, socket) do
    {:noreply, push_event(socket, "b:image_picker:pick", %{id: picked.id})}
  end

  def handle_async(:pick_library_image, _result, socket) do
    send(self(), {:toast, gettext("The image could not be copied for this field")})
    {:noreply, socket}
  end

  # Copying can mean reading the original from the CDN and writing a file, so
  # it runs beside the page: as this process would, in its site, with its
  # authorization scope, and in the E2E server's test sandbox.
  defp start_pick(socket, image_id) do
    user = socket.assigns.current_user
    config_target = socket.assigns.config_target
    scope = Brando.Authorization.Boundary.current_scope()
    parent = self()

    pick =
      Brando.Tenant.capture_context(fn ->
        if Application.get_env(Brando.config(:otp_app), :sql_sandbox),
          do: Ecto.Adapters.SQL.Sandbox.allow(Brando.Repo.repo(), parent, self())

        Brando.Authorization.Boundary.with_scope(scope, fn -> pick_for(image_id, config_target, user) end)
      end)

    start_async(socket, :pick_library_image, pick)
  end

  defp pick_for(image_id, config_target, user) do
    with :ok <- Brando.Authorization.Media.authorize(user, :image),
         {:ok, image} <- Brando.Images.get_image(image_id) do
      Brando.Images.for_config_target(image, config_target, user)
    end
  end

  def render(assigns) do
    ~H"""
    <div>
      <Content.drawer
        id={@id}
        title={if @picker_mode == :block_upload, do: gettext("Choose upload folder"), else: gettext("Images")}
        close={JS.push("cancel_pending_upload", target: @myself) |> toggle_drawer("##{@id}")}
        z={@z_index}
        wide
        light
        workspace
        icon="image"
        subtitle={
          if @picker_mode == :block_upload,
            do: gettext("Choose where to store these images."),
            else: gettext("Select an image from your library.")
        }
      >
        <:info>
          <.live_component
            module={FileBrowser}
            id={"#{@id}-top"}
            section={:top}
            mode={:drawer}
            root_name={gettext("Images")}
            target={@myself}
            upload_root={@upload_root}
            current_folder={@current_folder}
            breadcrumbs={@breadcrumbs}
            recent_folders={@recent_folders_for_root}
          >
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
          go_root_event="picker_go_root"
          go_parent_event="picker_go_parent"
          leave_root={@library_offered? and @scope == :field}
        >
          <:main_header>
            <div class="image-picker-main-header">
              <%!-- The full path, not "Root folder": this browser is rooted at the
                    field's own upload path, so "root" names somewhere different
                    for every field and tells you nothing about where you are. --%>
              <div class="image-picker-main-heading">
                <nav
                  :if={@library_offered?}
                  class="pill-tabs pill-tabs--small image-picker-scope"
                  aria-label={gettext("Images to choose from")}
                >
                  <button
                    type="button"
                    aria-pressed={to_string(@scope == :field)}
                    phx-click="set_scope"
                    phx-value-scope="field"
                    phx-target={@myself}
                  >
                    {gettext("Set up for this field")}
                  </button>
                  <button
                    type="button"
                    aria-pressed={to_string(@scope == :library)}
                    phx-click="set_scope"
                    phx-value-scope="library"
                    phx-target={@myself}
                  >
                    {gettext("Whole library")}
                  </button>
                </nav>
                <h3>{FolderBrowser.absolute_folder(@current_folder, @upload_root)}</h3>
                <p class="image-picker-main-hint">{scope_hint(@scope, @library_offered?)}</p>
              </div>
              <div class="image-picker-main-actions">
                <form
                  id={"image-picker-search-#{@id}"}
                  phx-change="search_images"
                  phx-target={@myself}
                  phx-submit="search_images"
                >
                  <input
                    type="search"
                    name="search"
                    value={@search}
                    class="image-picker-search"
                    placeholder={gettext("Search by name or title")}
                    aria-label={gettext("Search by name or title")}
                    phx-debounce="250"
                    autocomplete="off"
                  />
                </form>
                <span>
                  {ngettext("%{count} image", "%{count} images", @image_count, count: @image_count)}
                </span>
                <div
                  :if={@upload_target}
                  id={"image-picker-upload-#{@id}"}
                  phx-hook="Brando.UploadTrigger"
                  data-click-mode="trigger"
                  {@upload_target}
                >
                  <button type="button" class="folder-action upload-trigger">
                    <.icon name="upload" />{gettext("Upload here")}
                  </button>
                  <input type="file" class="file-input" multiple accept="image/*" aria-label={gettext("Upload images")} />
                </div>
              </div>
            </div>
          </:main_header>

          <%!-- The list is also a drop zone for new images, uploaded to the
                folder on screen with the field's own image config. --%>
          <div
            id={"image-picker-drawer-#{@id}"}
            class="image-picker list"
            phx-hook={@upload_target && "Brando.UploadTrigger"}
            data-click-mode="trigger"
            {@upload_target || []}
          >
            <%= if @image_count == 0 do %>
              <div class="image-picker-empty">
                <.icon name="image" />
                <h4>{gettext("No images in this folder")}</h4>
                <%= if @library_offered? and @scope == :field do %>
                  <p>
                    {gettext("Upload one here, or pick one from the whole library to have it cut to this field's sizes.")}
                  </p>
                  <button
                    type="button"
                    class="folder-action"
                    phx-click="set_scope"
                    phx-value-scope="library"
                    phx-target={@myself}
                  >
                    {gettext("Show the whole library")}
                  </button>
                <% else %>
                  <p>{gettext("Choose another folder to find an image")}</p>
                <% end %>
              </div>
            <% end %>

            <div
              :if={@organize_selected != []}
              class="image-picker-organize-bar"
              draggable="true"
              title={gettext("Drag to a folder")}
            >
              <.icon name="maximize-2" />
              <span>
                {ngettext(
                  "%{count} image selected for organizing",
                  "%{count} images selected for organizing",
                  length(@organize_selected),
                  count: length(@organize_selected)
                )}
              </span>
              <%!-- Filled by the ImagePickerGrid hook from the selected rows, which
                    may be scrolled far out of view. --%>
              <div
                id={"image-picker-organize-thumbs-#{@id}"}
                class="image-picker-organize-thumbs"
                phx-update="ignore"
              >
              </div>
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

            <%!-- The hook sits on a wrapper: LiveView gives an element with
                  phx-viewport-bottom its own InfiniteScroll hook in place of
                  the one in its phx-hook. --%>
            <div
              id={"image-picker-grid-#{@id}"}
              class="image-picker-grid"
              phx-hook="Brando.ImagePickerGrid"
              data-target-component={@myself}
              data-event-target={@event_target}
              data-thumbs-id={"image-picker-organize-thumbs-#{@id}"}
            >
              <div
                id={"image-picker-rows-#{@id}"}
                class="image-picker-rows"
                phx-update="stream"
                phx-viewport-bottom={JS.push("load_more_images", target: @myself)}
              >
                <.image_row
                  :for={{dom_id, image} <- @streams.visible_images}
                  id={dom_id}
                  image={image}
                  selected={Enum.any?(@selected_images, &same_item_id?(&1, image.id))}
                  multi={@multi}
                  event_target={@event_target}
                  picker_mode={@picker_mode}
                  from_library={@scope == :library}
                  myself={@myself}
                />
              </div>
            </div>
            <button
              :if={@rendered_count < @image_count}
              type="button"
              class="image-picker-more"
              phx-click="load_more_images"
              phx-target={@myself}
            >
              {gettext("Show more (%{count} left)", count: @image_count - @rendered_count)}
            </button>
          </div>
        </.live_component>
        <:footer :if={@picker_mode == :block_upload}>
          <div class="image-picker-upload-callout">
            <div>
              <span :if={@pending_target_label} class="media-destination-target">{@pending_target_label}</span>
              <span class="media-destination-folder">{FolderBrowser.absolute_folder(@current_folder, @upload_root)}</span>
              <%= if @pending_video_count > 0 do %>
                <div>
                  {ngettext(
                    "%{count} image to this folder",
                    "%{count} images to this folder",
                    @pending_file_count - @pending_video_count
                  )}
                </div>
                <div>
                  {ngettext("%{count} video to %{folder}", "%{count} videos to %{folder}", @pending_video_count,
                    folder: @pending_video_folder
                  )}
                </div>
              <% else %>
                <%= if @pending_file_count == 0 do %>
                  {gettext("Uploads to this field go to this folder")}
                <% else %>
                  {ngettext(
                    "Upload %{count} file to this folder",
                    "Upload %{count} files to this folder",
                    @pending_file_count
                  )}
                <% end %>
              <% end %>
            </div>
            <div class="media-destination-actions">
              <button
                class="primary small"
                type="button"
                phx-click={JS.push("confirm_block_upload_folder", target: @myself) |> toggle_drawer("#image-picker")}
              >
                {if @pending_file_count == 0, do: gettext("Use this folder"), else: gettext("Upload here")}
              </button>
              <button
                type="button"
                class="media-button"
                phx-click={JS.push("cancel_pending_upload", target: @myself) |> toggle_drawer("#image-picker")}
              >{gettext("Cancel")}</button>
            </div>
          </div>
        </:footer>
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
    <%!-- `selected` is rendered as well as pushed: opening the picker streams
    its rows in after the `image_picker_selection_changed` event has run, so a
    row that only waited for the hook came in unmarked. The hook still owns
    every later change. --%>
    <div
      id={@id}
      class={["image-picker__image", @selected && "selected"]}
      data-id={@image.id}
      data-selectable={to_string(@picker_mode == :select)}
      role={if @picker_mode == :select, do: "button"}
      tabindex={if @picker_mode == :select, do: "0"}
      phx-key="Enter"
      phx-keydown={if @picker_mode == :select, do: JS.exec("phx-click")}
      phx-click={
        cond do
          @picker_mode != :select ->
            nil

          # Marked at once, before the round trip through the field; the
          # selection state the picker pushes back then confirms it.
          @multi ->
            "selected" |> JS.toggle_class() |> JS.push("select_image", target: @event_target)

          @from_library ->
            "pick_library_image"
            |> JS.push(target: @myself)
            |> JS.push("picker_closed", target: @myself)
            |> toggle_drawer("#image-picker")

          true ->
            "select_image"
            |> JS.push(target: @event_target)
            |> JS.push("picker_closed", target: @myself)
            |> toggle_drawer("#image-picker")
        end
      }
      phx-value-id={@image.id}
    >
      <span class="image-picker__selected-indicator" aria-hidden="true">
        <.icon name="check" />
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
            <.icon name="circle-ellipsis" />
          </button>
          <ul id={@menu_id} class="image-picker-action-dropdown hidden">
            <li>
              <button
                type="button"
                phx-click={
                  JS.push("edit_image_from_picker", target: @myself, value: %{id: @image.id})
                  |> hide_dropdown("##{@menu_id}")
                  |> toggle_drawer("#image-picker")
                  |> open_image_editor_drawer()
                }
              >
                <.icon name="square-pen" />
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
                <.icon name="trash" />
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
    |> assign_new(:current_user, fn -> nil end)
    |> assign_new(:scope, fn -> :field end)
    |> assign_new(:library_offered?, fn -> false end)
    |> assign_new(:config_target, fn -> nil end)
    |> assign_new(:event_target, fn -> nil end)
    |> assign_new(:selected_images, fn -> [] end)
    |> assign_new(:picker_mode, fn -> :select end)
    |> assign_new(:opened?, fn -> false end)
    |> assign_new(:pending_upload_name, fn -> nil end)
    |> assign_new(:pending_file_count, fn -> 0 end)
    |> assign_new(:form_id, fn -> nil end)
    |> assign_new(:upload_target, fn -> nil end)
    |> assign_new(:upload_in_form?, fn -> false end)
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
    |> assign_new(:rendered_count, fn -> 0 end)
    |> assign_new(:search, fn -> "" end)
  end

  defp assign_folder_state(socket, requested_folder) do
    scope = socket.assigns.scope
    upload_root = picker_upload_root(if scope == :library, do: :all, else: socket.assigns.config_target)
    images = list_images(socket.assigns.config_target, scope)

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

    visible_images =
      images
      |> FolderBrowser.entries_in_folder(current_folder, upload_root)
      |> filter_by_search(socket.assigns[:search])

    child_folders = FolderBrowser.child_folders(folders, current_folder)
    breadcrumbs = FolderBrowser.breadcrumbs(current_folder)

    recent_folders_for_root =
      PickerFolders.recent_folders_for_root(socket.assigns.recent_folders, upload_root, &folder_under_root?/2)

    socket
    |> assign(:upload_root, upload_root)
    |> assign(:folders, folders)
    |> assign(:current_folder, current_folder)
    |> assign(:image_count, length(visible_images))
    |> assign(:visible_item_ids, Enum.map(visible_images, & &1.id))
    |> assign(:rendered_count, min(@page_size, length(visible_images)))
    |> stream(:visible_images, load_page(Enum.take(visible_images, @page_size)), reset: true)
    |> assign(:child_folders, child_folders)
    |> assign(:breadcrumbs, breadcrumbs)
    |> assign(:recent_folders_for_root, recent_folders_for_root)
    |> assign(:upload_target, upload_target(socket, upload_root, current_folder))
  end

  # Matches the file name and the title in any language, ignoring case.
  defp filter_by_search(images, search) when search in [nil, ""], do: images

  defp filter_by_search(images, search) do
    needle = String.downcase(search)

    Enum.filter(images, fn image ->
      titles = if is_map(image.title), do: Map.values(image.title), else: [image.title]

      [Path.basename(image.path || "") | titles]
      |> Enum.any?(&(is_binary(&1) and String.contains?(String.downcase(&1), needle)))
    end)
  end

  # The next page of the folder's images, appended to the list. Only the ids
  # are kept between pages, so the rows are loaded again by id, in order.
  defp stream_next_page(%{assigns: %{visible_item_ids: ids, rendered_count: rendered}} = socket) do
    case Enum.slice(ids, rendered, @page_size) do
      [] ->
        socket

      page_ids ->
        socket
        |> assign(:rendered_count, rendered + length(page_ids))
        |> stream(:visible_images, load_page(page_ids))
    end
  end

  defp stream_next_page(socket), do: socket

  # The rows of `images_or_ids`, in their order
  defp load_page([]), do: []

  defp load_page(images_or_ids) do
    ids = Enum.map(images_or_ids, &item_id/1)
    by_id = ids |> load_images() |> Map.new(&{&1.id, &1})
    for id <- ids, image = by_id[id], do: image
  end

  defp item_id(%{id: id}), do: id
  defp item_id(id), do: id

  defp load_images(ids) do
    import Ecto.Query, only: [from: 2]
    Brando.Repo.all(from(i in Brando.Images.Image, where: i.id in ^ids, select: struct(i, ^@list_fields)))
  end

  # A closed picker keeps nothing on the page: its rows sat in the form's DOM
  # (1000+ in a big folder) and every later patch of the form walked them.
  # Opening it again loads the folder afresh anyway.
  defp close_list(socket) do
    socket
    |> assign(:opened?, false)
    |> assign(:search, "")
    |> assign(:organize_selected, [])
    |> assign(:last_organize_selected_id, nil)
    |> assign(:visible_item_ids, [])
    |> assign(:rendered_count, 0)
    |> stream(:visible_images, [], reset: true)
  end

  # The UploadTrigger data for uploading into the folder on screen, with the
  # field's own image config, or nil where the picker can't take an upload:
  # choosing a block upload's folder, browsing the whole library (`:all`), or
  # outside a form (`upload_in_form?`, set where the form renders the picker),
  # whose root carries the topic the upload is delivered on.
  defp upload_target(
         %{assigns: %{picker_mode: :select, upload_in_form?: true, scope: :field, config_target: config_target}} =
           socket,
         root,
         folder
       )
       when is_binary(config_target) do
    [
      {"data-kind", "image_picker"},
      {"data-component-id", socket.assigns.id},
      {"data-asset-type", "image"},
      {"data-config-target", config_target},
      {"data-folder", FolderBrowser.absolute_folder(folder, root)},
      {"data-folder-id", FolderBrowser.folder_id_for(folder, root)}
    ]
  end

  defp upload_target(_socket, _root, _folder), do: nil

  # Opening for a field starts on its own images. A folder from the library
  # means nothing there, but the field's last folder, and folders made in the
  # picker, are kept for the next opening.
  defp leave_library(%{assigns: %{scope: :library}} = socket),
    do: assign(socket, scope: :field, custom_folders: [], current_folder: "")

  defp leave_library(socket), do: assign(socket, :scope, :field)

  # The library's own folders differ from the field's, so a switch starts
  # over in `folder`, relative to the new scope's root.
  defp switch_scope(socket, scope, folder) do
    socket
    |> assign(:scope, scope)
    |> assign(:custom_folders, [])
    |> assign(:organize_selected, [])
    |> assign(:last_organize_selected_id, nil)
    |> assign(:current_folder, "")
    |> assign_folder_state(folder)
  end

  defp scope_hint(:library, _offered?) do
    gettext(
      "The whole library. An image set up for another field is copied and cut to this field's sizes when you pick it."
    )
  end

  defp scope_hint(:field, true) do
    gettext(
      "Only images set up for this field. Whole library offers the rest, cut to this field's sizes when you pick one."
    )
  end

  defp scope_hint(:field, false) do
    gettext("Only images set up for this field. The rest of the library is cut to other sizes and is not offered here.")
  end

  defp picker_upload_root(:all), do: FolderBrowser.scope_for(nil)
  defp picker_upload_root(config_target), do: FolderBrowser.upload_root(config_target)

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
