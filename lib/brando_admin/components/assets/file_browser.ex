defmodule BrandoAdmin.Components.Assets.FileBrowser do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Images.FolderBrowser
  alias Phoenix.LiveView.JS

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign_defaults()
     |> assign(assigns)}
  end

  def render(%{section: :top} = assigns) do
    ~H"""
    <div id={@id} class="assets-file-browser assets-file-browser--top">
      <.browser_top {assigns} />
    </div>
    """
  end

  def render(%{section: :browser} = assigns) do
    ~H"""
    <div id={@id} class="assets-file-browser assets-file-browser--browser">
      <.browser_main {assigns} />
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div id={@id} class={["assets-file-browser", "assets-file-browser--#{@mode}"]}>
      <.browser_top {assigns} />
      <.browser_main {assigns} />
    </div>
    """
  end

  defp browser_top(assigns) do
    ~H"""
    <div class="image-picker-top">
      <%= if @top_lead != [] do %>
        {render_slot(@top_lead)}
      <% end %>

      <div class="image-picker-toolbar">
        <nav class="image-picker-path" aria-label={gettext("Folder path")}>
          <%= for {crumb, idx} <- Enum.with_index(@breadcrumbs) do %>
            <button
              type="button"
              class={["path-link", crumb.folder == @current_folder && "active"]}
              phx-click={push_browser_event(@go_folder_event, @target, %{folder: crumb.folder})}
            >
              {if crumb.folder == "", do: root_label(@upload_root), else: crumb.label}
            </button>
            <span :if={idx < length(@breadcrumbs) - 1} class="path-separator">/</span>
          <% end %>
        </nav>

        <%= if @toolbar_actions != [] do %>
          {render_slot(@toolbar_actions)}
        <% end %>
      </div>

      <div :if={@show_recent_folders && @recent_folders != []} class="image-picker-recent-folders">
        <span class="label">{gettext("Recent folders")}</span>
        <%= for folder <- @recent_folders do %>
          <button
            type="button"
            class="folder-pill subtle"
            phx-click={push_browser_event(@go_recent_event, @target, %{folder: folder})}
          >
            {folder_label_for_display(FolderBrowser.relative_folder(folder, @upload_root), @upload_root)}
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  defp browser_main(assigns) do
    ~H"""
    <div class={["image-picker-browser", @mode == :inline && "image-picker-browser--inline"]}>
      <aside class="image-picker-folders">
        <div class="image-picker-folders-header">
          <div>
            <h3>{@folders_title}</h3>
            <p>{@folders_description}</p>
          </div>
          <div class="folder-actions">
            <button
              type="button"
              class="folder-action icon-only"
              phx-click={push_browser_event(@go_parent_event, @target)}
              disabled={@current_folder == ""}
              title={gettext("Up")}
              aria-label={gettext("Up")}
            >
              <.icon name="hero-arrow-up-mini" />
            </button>
            <button
              type="button"
              class="folder-action"
              phx-click={push_browser_event(@go_root_event, @target)}
              disabled={@current_folder == ""}
            >
              {gettext("Root")}
            </button>
          </div>
        </div>

        <button
          :if={!@show_new_folder_form}
          type="button"
          class="new-folder-trigger"
          phx-click={@show_new_folder_event}
          phx-target={@target}
        >
          <.icon name="hero-plus-small" />
          {gettext("New folder")}
        </button>

        <form
          :if={@show_new_folder_form}
          phx-submit={@create_folder_event}
          phx-target={@target}
          class="new-folder-form"
        >
          <input
            id={"#{@id}-new-folder"}
            class="text small"
            type="text"
            name="folder[name]"
            value={@new_folder}
            placeholder={gettext("Folder name")}
            phx-mounted={JS.focus()}
          />
          <div class="new-folder-actions">
            <button
              type="submit"
              class="folder-icon-button confirm"
              title={gettext("Create folder")}
              aria-label={gettext("Create folder")}
            >
              <.icon name="hero-check-circle" />
            </button>
            <button
              type="button"
              class="folder-icon-button cancel"
              title={gettext("Cancel")}
              aria-label={gettext("Cancel")}
              phx-click={@cancel_new_folder_event}
              phx-target={@target}
            >
              <.icon name="hero-x-mark" />
            </button>
          </div>
        </form>

        <div class="folder-list">
          <%= if @child_folders == [] do %>
            <div class="empty">{gettext("No subfolders in this location")}</div>
          <% end %>

          <%= for folder <- @child_folders do %>
            <button
              id={folder_row_id(@id, folder)}
              type="button"
              class={["folder-row", folder == @current_folder && "active"]}
              phx-click={push_browser_event(@go_folder_event, @target, %{folder: folder})}
              phx-hook={if @enable_folder_drop, do: "Brando.AssetFolderDrop"}
              data-drop-event={@folder_drop_event}
              data-drop-folder={folder}
              data-drop-target={@target}
            >
              <.icon name="hero-folder" />
              <span class="folder-name">{folder_label(folder, @current_folder)}</span>
            </button>
          <% end %>
        </div>
      </aside>

      <section id={@main_id} class="image-picker-main">
        <%= if @main_header != [] do %>
          {render_slot(@main_header)}
        <% end %>
        {render_slot(@inner_block)}
      </section>
    </div>
    """
  end

  defp assign_defaults(socket) do
    socket
    |> assign_new(:mode, fn -> :drawer end)
    |> assign_new(:section, fn -> :all end)
    |> assign_new(:target, fn -> nil end)
    |> assign_new(:upload_root, fn -> "images/default" end)
    |> assign_new(:current_folder, fn -> "" end)
    |> assign_new(:breadcrumbs, fn -> [%{label: "Root", folder: ""}] end)
    |> assign_new(:recent_folders, fn -> [] end)
    |> assign_new(:show_recent_folders, fn -> true end)
    |> assign_new(:child_folders, fn -> [] end)
    |> assign_new(:show_new_folder_form, fn -> false end)
    |> assign_new(:new_folder, fn -> "" end)
    |> assign_new(:go_root_event, fn -> "go_root" end)
    |> assign_new(:go_folder_event, fn -> "go_folder" end)
    |> assign_new(:go_parent_event, fn -> "go_parent_folder" end)
    |> assign_new(:go_recent_event, fn -> "go_recent_folder" end)
    |> assign_new(:show_new_folder_event, fn -> "show_new_folder_form" end)
    |> assign_new(:cancel_new_folder_event, fn -> "cancel_new_folder_form" end)
    |> assign_new(:create_folder_event, fn -> "create_folder" end)
    |> assign_new(:folders_title, fn -> gettext("Folders") end)
    |> assign_new(:folders_description, fn -> gettext("Navigate and create folders") end)
    |> assign_new(:main_id, fn -> nil end)
    |> assign_new(:enable_folder_drop, fn -> false end)
    |> assign_new(:folder_drop_event, fn -> "assets_move_selected_to_folder" end)
    |> assign_new(:top_lead, fn -> [] end)
    |> assign_new(:toolbar_actions, fn -> [] end)
    |> assign_new(:main_header, fn -> [] end)
    |> assign_new(:inner_block, fn -> [] end)
  end

  defp push_browser_event(event, target), do: push_browser_event(event, target, nil)

  defp push_browser_event(event, target, value) do
    opts =
      []
      |> maybe_put_opt(:target, target)
      |> maybe_put_opt(:value, value)

    JS.push(event, opts)
  end

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp root_label(upload_root) do
    case FolderBrowser.normalize_folder(upload_root) do
      nil -> "Root"
      root -> root
    end
  end

  defp folder_label(folder, current_folder) do
    folder
    |> String.replace_prefix(current_folder <> "/", "")
    |> String.split("/", parts: 2)
    |> hd()
  end

  defp folder_label_for_display(folder, upload_root) do
    case FolderBrowser.relative_folder(folder, upload_root) do
      relative when relative in [nil, ""] -> root_label(upload_root)
      relative -> relative
    end
  end

  defp folder_row_id(component_id, folder) do
    safe_folder =
      folder
      |> String.replace("/", "-")
      |> String.replace(~r/[^a-zA-Z0-9_-]/, "")

    "#{component_id}-folder-row-#{safe_folder}"
  end
end
