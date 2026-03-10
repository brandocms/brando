defmodule BrandoAdmin.Images.ImageListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Images.Image
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Images.FolderBrowser
  alias Brando.Images

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> allow_upload(:images,
        accept: ~w(.jpg .jpeg .png .gif .webp .avif .svg),
        max_entries: 10,
        max_file_size: 10_000_000,
        auto_upload: true,
        progress: &handle_progress/3
      )
      |> assign(:recent_folders, [])
      |> assign(:custom_folders, [])
      |> assign(:folders, [""])
      |> assign(:child_folders, [])
      |> assign(:current_folder, "")
      |> assign(:current_folder_abs, nil)
      |> assign(:upload_root, FolderBrowser.scope_for(nil))
      |> assign(:upload_folder, nil)
      |> assign(:breadcrumbs, [%{label: "Root", folder: ""}])
      |> assign(:new_folder, "")
      |> assign_folder_state(nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign_folder_state(socket, params["filter:path"])}
  end

  @impl true
  def handle_event("validate", params, socket) do
    folder = get_in(params, ["upload", "folder"]) || socket.assigns.current_folder_abs
    {:noreply, assign(socket, :upload_folder, folder)}
  end

  def handle_event("assets_go_root", _, socket) do
    {:noreply, patch_folder_filter(socket, nil)}
  end

  def handle_event("assets_go_folder", %{"folder" => folder}, socket) do
    absolute_folder = FolderBrowser.absolute_folder(folder, socket.assigns.upload_root)
    {:noreply, patch_folder_filter(socket, absolute_folder)}
  end

  def handle_event("assets_go_parent", _, %{assigns: %{current_folder: ""}} = socket) do
    {:noreply, socket}
  end

  def handle_event("assets_go_parent", _, socket) do
    parent =
      socket.assigns.current_folder
      |> String.split("/", trim: true)
      |> Enum.drop(-1)
      |> Enum.join("/")

    absolute_parent = FolderBrowser.absolute_folder(parent, socket.assigns.upload_root)
    {:noreply, patch_folder_filter(socket, absolute_parent)}
  end

  def handle_event("assets_go_recent", %{"folder" => folder}, socket) do
    {:noreply, patch_folder_filter(socket, folder)}
  end

  def handle_event("assets_create_folder", %{"folder" => %{"name" => folder_name}}, socket) do
    cleaned = FolderBrowser.normalize_folder(folder_name)

    if cleaned do
      absolute =
        if socket.assigns.current_folder in ["", nil] do
          cleaned
        else
          Path.join(socket.assigns.current_folder, cleaned)
        end
        |> FolderBrowser.normalize_folder()

      case FolderBrowser.create_folder(absolute, socket.assigns.upload_root) do
        {:ok, _folder} ->
          {:noreply,
           socket
           |> assign(:custom_folders, Enum.uniq([absolute | socket.assigns.custom_folders]))
           |> patch_folder_filter(FolderBrowser.absolute_folder(absolute, socket.assigns.upload_root))}

        {:error, _reason} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_progress(:images, entry, socket) do
    if entry.done? do
      config_target = "default"
      {:ok, cfg} = Images.get_config_for(%{config_target: config_target})
      folder_id = FolderBrowser.folder_id_for(socket.assigns.current_folder, socket.assigns.upload_root)
      cfg = maybe_override_image_upload_path(cfg, socket.assigns.upload_folder || socket.assigns.current_folder_abs)

      case consume_uploaded_entry(socket, entry, fn %{path: path} ->
             case Images.Uploads.Schema.handle_upload(
                    %{
                      "image" => %Plug.Upload{filename: entry.client_name, content_type: entry.client_type, path: path},
                      "config_target" => config_target,
                      "folder_id" => folder_id
                    },
                    cfg,
                    socket.assigns.current_user
                  ) do
               {:ok, image} -> {:ok, image}
               {:error, reason} -> {:ok, {:upload_error, reason}}
             end
           end) do
        {:upload_error, _reason} ->
          send(self(), {:toast, gettext("Failed to upload image")})

        _image ->
          send(self(), {:toast, gettext("Image uploaded successfully")})
          update_list_entries(socket.assigns.schema)
      end
    end

    {:noreply, socket}
  end

  defp update_list_entries(schema) do
    topic = "brando:listing:content_listing_#{schema}_default"
    Phoenix.PubSub.broadcast(Brando.pubsub(), topic, {schema, [:entries, :updated], []})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Content.header title={gettext("Assets — Images")} subtitle={gettext("Overview")}>
      <form phx-change="validate" phx-drop-target={@uploads.images.ref}>
        <input type="hidden" name="upload[folder]" value={@current_folder_abs} />
        <label class="btn-stealth">
          <span>{gettext("Upload Images")}</span>
          <.live_file_input upload={@uploads.images} class="hidden" />
        </label>
      </form>
    </Content.header>

    <section class="assets-image-browser">
      <div class="assets-image-browser__current">
        <span>{gettext("Current folder")}</span>
        <code>{folder_label_for_display(@current_folder_abs)}</code>
      </div>

      <div class="assets-image-browser__breadcrumbs">
        <%= for crumb <- @breadcrumbs do %>
          <button
            type="button"
            class={["browser-chip", crumb.folder == @current_folder && "active"]}
            phx-click="assets_go_folder"
            phx-value-folder={crumb.folder}
          >
            {crumb.label}
          </button>
        <% end %>
      </div>

      <div class="assets-image-browser__controls">
        <button type="button" class="browser-chip subtle" phx-click="assets_go_parent" disabled={@current_folder == ""}>
          {gettext("Up")}
        </button>
        <button type="button" class="browser-chip subtle" phx-click="assets_go_root">
          {gettext("Root")}
        </button>

        <form phx-submit="assets_create_folder" class="assets-image-browser__new-folder">
          <input type="text" class="text small" name="folder[name]" placeholder={gettext("New folder")} />
          <button type="submit" class="browser-create">{gettext("Create")}</button>
        </form>
      </div>

      <div class="assets-image-browser__folders">
        <%= if @child_folders == [] do %>
          <span class="empty">{gettext("No subfolders")}</span>
        <% end %>

        <%= for folder <- @child_folders do %>
          <button type="button" class="browser-chip" phx-click="assets_go_folder" phx-value-folder={folder}>
            {folder_label(folder, @current_folder)}
          </button>
        <% end %>
      </div>

      <div :if={@recent_folders != []} class="assets-image-browser__recents">
        <span class="label">{gettext("Recent")}</span>
        <%= for folder <- @recent_folders do %>
          <button type="button" class="browser-chip subtle" phx-click="assets_go_recent" phx-value-folder={folder}>
            {folder_label_for_display(folder)}
          </button>
        <% end %>
      </div>
    </section>

    <.live_component
      module={Content.List}
      id={"content_listing_#{@schema}_default"}
      schema={@schema}
      current_user={@current_user}
      uri={@uri}
      params={@params}
      listing={:default}
    />
    """
  end

  defp assign_folder_state(socket, path_filter) do
    {:ok, images} = Images.list_images(%{select: [:path, :folder_id], order: "desc id"})

    folders =
      FolderBrowser.folders_from_images(images, socket.assigns.upload_root)
      |> Kernel.++(socket.assigns.custom_folders)
      |> Enum.map(&(FolderBrowser.normalize_folder(&1) || ""))
      |> Enum.uniq()
      |> Enum.sort()

    current_folder = FolderBrowser.relative_folder(path_filter, socket.assigns.upload_root) || ""
    current_folder = if current_folder in folders, do: current_folder, else: ""

    current_folder_abs =
      if current_folder == "" do
        nil
      else
        FolderBrowser.absolute_folder(current_folder, socket.assigns.upload_root)
      end

    child_folders = FolderBrowser.child_folders(folders, current_folder)
    breadcrumbs = FolderBrowser.breadcrumbs(current_folder)

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
  end

  defp patch_folder_filter(socket, folder) do
    uri = socket.assigns.uri
    current_params = URI.decode_query(uri.query || "")

    new_params =
      current_params
      |> Map.put("filter:path", folder || "")
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
      |> URI.encode_query()

    to =
      if new_params == "" do
        uri.path
      else
        uri.path <> "?" <> new_params
      end

    push_patch(socket, to: to)
  end

  defp maybe_override_image_upload_path(cfg, nil), do: cfg

  defp maybe_override_image_upload_path(%Brando.Type.ImageConfig{} = cfg, folder) do
    resolved_folder = FolderBrowser.absolute_folder(folder, cfg.upload_path)

    if resolved_folder do
      %{cfg | upload_path: resolved_folder}
    else
      cfg
    end
  end

  defp folder_label(folder, current_folder) do
    folder
    |> String.replace_prefix(current_folder <> "/", "")
    |> String.split("/", parts: 2)
    |> hd()
  end

  defp folder_label_for_display(folder) do
    case FolderBrowser.relative_folder(folder, FolderBrowser.scope_for(nil)) do
      "" -> "Root"
      value -> value
    end
  end
end
