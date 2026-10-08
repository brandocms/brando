defmodule BrandoAdmin.CommandPaletteLive do
  @moduledoc """
  The command palette (⌘K, Ctrl+K elsewhere): one search across entries,
  assets, settings and actions, from any admin screen.

  A sticky LiveView of its own, so searching never touches the screen under
  it — an entry editor keeps its state and focus. The `Brando.CommandPalette`
  hook opens the dialog, moves the selection and keeps the recent places; this
  view answers queries with `BrandoAdmin.CommandPalette.results/4`.
  """
  use BrandoAdmin, :child_live_view
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.CommandPalette

  on_mount {BrandoAdmin.UserAuth, :mount_current_user}
  on_mount {Brando.Tenant.LiveView, :default}
  on_mount {BrandoAdmin.Authorization, :default}

  def mount(_params, _session, socket) do
    put_locale(socket.assigns.current_user)

    {:ok,
     assign(socket,
       context: nil,
       query: "",
       recent: [],
       current_path: nil,
       groups: [],
       site_key: socket.assigns[:current_site] && socket.assigns.current_site.key
     )}
  end

  defp put_locale(%{language: language}), do: Gettext.put_locale(to_string(language))
  defp put_locale(_), do: nil

  # Permissions and the menu are read again each time the palette opens.
  def handle_event("open", params, socket) do
    context = CommandPalette.context(socket.assigns.current_user, socket.assigns[:current_site])

    {:noreply,
     socket
     |> assign(
       context: context,
       query: "",
       recent: recent_param(params["recent"]),
       current_path: if(is_binary(params["path"]), do: params["path"])
     )
     |> assign_groups()}
  end

  def handle_event("search", %{"q" => query}, %{assigns: %{context: nil}} = socket) do
    handle_event(
      "search",
      %{"q" => query},
      assign(socket, :context, CommandPalette.context(socket.assigns.current_user, socket.assigns[:current_site]))
    )
  end

  def handle_event("search", %{"q" => query}, socket) when is_binary(query) do
    {:noreply, socket |> assign(:query, String.slice(query, 0, 200)) |> assign_groups()}
  end

  def handle_event("search", _params, socket), do: {:noreply, socket}

  # Nothing is kept for the next opening, which starts empty.
  def handle_event("close", _params, socket), do: {:noreply, assign(socket, query: "", groups: [])}

  defp assign_groups(socket) do
    %{context: context, query: query, recent: recent, current_path: current_path} = socket.assigns
    assign(socket, :groups, CommandPalette.results(context, query, recent, current_path: current_path))
  end

  defp recent_param(recent) when is_list(recent), do: recent |> Enum.filter(&is_map/1) |> Enum.take(20)
  defp recent_param(_), do: []

  def render(assigns) do
    ~H"""
    <div
      id="command-palette"
      phx-hook="Brando.CommandPalette"
      data-user={@current_user && @current_user.id}
      data-site={@site_key}
    >
      <dialog
        id="command-palette-dialog"
        class="command-palette"
        aria-label={gettext("Search and commands")}
        phx-mounted={JS.ignore_attributes(["open"])}
      >
        <form id="command-palette-form" class="command-palette-search" phx-change="search" phx-submit="search">
          <.icon name="search" class="command-palette-search-icon" />
          <input
            id="command-palette-input"
            type="text"
            name="q"
            value={@query}
            role="combobox"
            aria-autocomplete="list"
            aria-expanded="true"
            aria-controls="command-palette-results"
            aria-label={gettext("Search entries, settings and actions")}
            placeholder={gettext("Search, or type > for commands")}
            autocomplete="off"
            spellcheck="false"
            phx-debounce="100"
          />
          <button type="button" class="command-palette-esc" data-palette-close aria-label={gettext("Close")}>
            <kbd>esc</kbd>
          </button>
        </form>
        <div
          id="command-palette-results"
          class="command-palette-results"
          role="listbox"
          aria-label={gettext("Results")}
          data-query={@query}
        >
          <p :if={@query != "" and nothing_found?(@groups)} class="command-palette-empty" role="status">
            {gettext("No titles match “%{query}”", query: @query)}
          </p>
          <div
            :for={group <- @groups}
            id={"command-palette-group-#{group.key}"}
            class="command-palette-group"
            role="group"
            aria-labelledby={"command-palette-heading-#{group.key}"}
          >
            <div id={"command-palette-heading-#{group.key}"} class="command-palette-heading" role="presentation">
              {group.label}
            </div>
            <.item :for={item <- group.items} item={item} />
          </div>
        </div>
        <footer class="command-palette-footer" aria-hidden="true">
          <span class="command-palette-hint"><kbd>↑</kbd><kbd>↓</kbd>{gettext("move")}</span>
          <span class="command-palette-hint"><kbd>↵</kbd>{gettext("open")}</span>
          <span class="command-palette-hint">
            <kbd><span class="shortcut-mac">⌘</span><span class="shortcut-other">Ctrl</span></kbd><kbd>↵</kbd>{gettext(
              "open in new tab"
            )}
          </span>
          <span class="command-palette-hint commands"><kbd>&gt;</kbd>{gettext("commands")}</span>
        </footer>
      </dialog>
    </div>
    """
  end

  attr :item, :map, required: true

  defp item(%{item: %{kind: :entry}} = assigns) do
    ~H"""
    <.link
      id={@item.id}
      navigate={@item.url}
      class="command-palette-item is-entry"
      role="option"
      aria-selected="false"
      tabindex="-1"
      data-palette-item
    >
      <span class="command-palette-cover">
        <img :if={is_binary(@item.cover) and @item.cover != ""} src={@item.cover} alt="" loading="lazy" />
        <.icon :if={!is_binary(@item.cover) or @item.cover == ""} name={@item.icon} />
      </span>
      <span class="command-palette-copy">
        <span class="command-palette-label">{@item.label}</span>
        <span class="command-palette-meta">
          <span>{@item.type}</span><span :if={@item.language}>{@item.language}</span>
        </span>
      </span>
      <span :if={@item.status} class="command-palette-status" data-status={@item.status}>
        <i aria-hidden="true"></i><span>{status_label(@item.status)}</span>
      </span>
      <kbd class="command-palette-enter" aria-hidden="true">↵</kbd>
    </.link>
    """
  end

  defp item(assigns) do
    ~H"""
    <.link
      id={@item.id}
      navigate={@item.url}
      class={["command-palette-item", "is-#{@item.kind}"]}
      role="option"
      aria-selected="false"
      tabindex="-1"
      data-palette-item
    >
      <.icon name={@item.icon} class="command-palette-icon" />
      <span class="command-palette-copy">
        <span class="command-palette-label">{@item.label}</span>
        <span :if={@item[:detail]} class="command-palette-meta"><span>{@item.detail}</span></span>
      </span>
      <span :if={@item[:count]} class="command-palette-count">{@item.count}</span>
      <kbd class="command-palette-enter" aria-hidden="true">↵</kbd>
    </.link>
    """
  end

  # Only the row to the search page: no title, action or setting matches
  defp nothing_found?(groups), do: Enum.all?(groups, fn group -> Enum.all?(group.items, &(&1.kind == :search)) end)

  defp status_label(:published), do: gettext("Published")
  defp status_label(:draft), do: gettext("Draft")
  defp status_label(:pending), do: gettext("Pending")
  defp status_label(:disabled), do: gettext("Disabled")
  defp status_label(_), do: gettext("Not set")
end
