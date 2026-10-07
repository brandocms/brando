defmodule BrandoAdmin.Components.Form.BlockField.ModulePicker do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content

  # The "Recently used" rail entry. Not a namespace a module can have.
  @recent_key "__recent"
  @recent_limit 5

  def mount(socket) do
    {:ok,
     assign(socket,
       active_namespace: nil,
       module_set: "all",
       show: false,
       query: "",
       collection: false,
       modules_by_namespace: [],
       recent_ids: [],
       recent_key: @recent_key
     )}
  end

  def render(assigns) do
    groups = visible_groups(assigns)

    # Counts follow the search: each group says how many of its modules match,
    # so you can see where else a name turns up while one group is selected.
    query = String.trim(assigns[:query] || "")

    namespace_counts =
      for {translated_namespace, _map, modules} <- assigns.modules_by_namespace,
          translated_namespace not in [nil, ""],
          do: {translated_namespace, Enum.count(modules, &matches?(&1, query))}

    total_count =
      Enum.reduce(assigns.modules_by_namespace, 0, fn {_, _, modules}, acc ->
        acc + Enum.count(modules, &matches?(&1, query))
      end)

    assigns =
      assigns
      |> assign(:groups, groups)
      |> assign(:namespace_counts, namespace_counts)
      |> assign(:total_count, total_count)
      |> assign(:recent_count, length(recent_modules(assigns)))
      |> assign(:extras?, !assigns.collection and (!assigns[:hide_fragments] or !assigns[:hide_sections]))

    # A palette: the search field is the header, the groups a rail on the
    # left, and each module a row with its sketch, name and description. The
    # first row is marked, so Enter inserts it straight from the search field.
    ~H"""
    <div>
      <Content.modal
        title={gettext("Add content block")}
        id={@id}
        layout="palette"
        close={JS.push("close_modal", target: @myself) |> hide_modal("##{@id}")}
      >
        <div :if={@show} class="module-picker">
          <div class="module-picker-search">
            <.icon name="search" />
            <input
              type="text"
              name="q"
              value={@query}
              phx-keyup="search"
              phx-target={@myself}
              phx-debounce="120"
              phx-mounted={JS.focus()}
              phx-hook="Brando.ModulePickerKeys"
              id={"#{@id}-search"}
              autocomplete="off"
              spellcheck="false"
              placeholder={gettext("Add a block – search modules…")}
              aria-label={gettext("Search modules")}
            />
            <button
              :if={@query != ""}
              type="button"
              class="module-picker-clear"
              phx-click="clear_search"
              phx-target={@myself}
              aria-label={gettext("Clear search")}
            >
              <.icon name="x" />
            </button>
            <button
              type="button"
              class="module-picker-close"
              phx-click={JS.push("close_modal", target: @myself) |> hide_modal("##{@id}")}
              aria-label={gettext("Close")}
            >
              <.icon name="x" />
            </button>
          </div>

          <div class="module-picker-body">
            <nav class={["module-picker-namespaces", @query != "" && "is-searching"]} aria-label={gettext("Module groups")}>
              <button
                :if={@recent_count > 0 and @query == ""}
                type="button"
                class={["module-picker-namespace", @active_namespace == @recent_key && "active"]}
                phx-click="toggle_namespace"
                phx-target={@myself}
                phx-value-id={@recent_key}
              >
                <span class="label">{gettext("Recently used")}</span>
                <span class="count">{@recent_count}</span>
              </button>
              <button
                type="button"
                class={["module-picker-namespace", is_nil(@active_namespace) && "active"]}
                phx-click="toggle_namespace"
                phx-target={@myself}
                phx-value-id=""
              >
                <span class="label">{gettext("Everything")}</span>
                <span class="count">{@total_count}</span>
              </button>
              <button
                :for={{namespace, count} <- @namespace_counts}
                :key={namespace}
                type="button"
                class={["module-picker-namespace", @active_namespace == namespace && "active", count == 0 && "is-empty"]}
                phx-click="toggle_namespace"
                phx-target={@myself}
                phx-value-id={namespace}
              >
                <span class="label">{namespace}</span>
                <span class="count">{count}</span>
              </button>

              <div :if={@extras?} class="module-picker-extras">
                <button
                  :if={!@hide_sections}
                  type="button"
                  phx-click={JS.push("insert_container", target: @myself) |> hide_modal("##{@id}")}
                  data-popover={gettext("A section holds other blocks, with its own background and spacing.")}
                >
                  <.icon name="app-window" />
                  {gettext("Container")}
                </button>
                <button
                  :if={!@hide_fragments}
                  type="button"
                  phx-click={JS.push("insert_fragment", target: @myself) |> hide_modal("##{@id}")}
                  data-popover={
                    gettext("A fragment is shared content, edited in one place and shown the same wherever it is inserted.")
                  }
                >
                  <.icon name="puzzle" />
                  {gettext("Fragment")}
                </button>
              </div>
            </nav>

            <div class="module-picker-results" data-query={@query}>
              <section :for={{namespace, modules} <- @groups} :key={namespace || "-"} class="module-picker-group">
                <h3 :if={namespace not in [nil, ""]} class="module-picker-group-title">{namespace}</h3>
                <button
                  :for={module <- modules}
                  :key={{namespace, module.library_origin, module.id}}
                  type="button"
                  class="module-row"
                  data-color={module.color}
                  data-module-ref={Brando.Content.SharedLibrary.encode_reference(module.library_origin, module.id)}
                  aria-label={translate(module.name)}
                  phx-click={JS.push("insert_module", target: @myself) |> hide_modal("##{@id}")}
                  phx-value-module-id={Brando.Content.SharedLibrary.encode_reference(module.library_origin, module.id)}
                >
                  <span class="module-row-sketch" aria-hidden="true">
                    <img :if={module.svg} src={"data:image/svg+xml;base64,#{module.svg}"} alt="" />
                    <.icon :if={!module.svg} name={module_icon(module)} />
                  </span>
                  <span class="module-row-text">
                    <span class="module-row-name">
                      {translate(module.name)}
                      <%!-- Origin only earns a badge when it distinguishes this
                            module from the others on screen. --%>
                      <span :if={module.library_origin == :shared} class="badge">
                        <%= if module.source_module_id do %>
                          {gettext("customized")}
                        <% else %>
                          {gettext("shared")}
                        <% end %>
                      </span>
                      <span :if={module.update_available} class="badge warning">
                        {gettext("update available")}
                      </span>
                    </span>
                    <span :if={translate(module.help_text) != ""} class="module-row-help">
                      {translate(module.help_text)}
                    </span>
                  </span>
                  <span class="module-row-enter" aria-hidden="true">↵ {gettext("Insert")}</span>
                </button>
              </section>

              <p :if={@groups == []} class="module-picker-empty">
                {gettext("No modules match \"%{query}\"", query: @query)}
              </p>
            </div>
          </div>

          <footer class="module-picker-keys" aria-hidden="true">
            <span><kbd>↑</kbd> <kbd>↓</kbd> {gettext("choose")}</span>
            <span><kbd>↵</kbd> {gettext("insert")}</span>
            <span><kbd>esc</kbd> {gettext("close")}</span>
          </footer>
        </div>
      </Content.modal>
    </div>
    """
  end

  def update(%{event: :refresh_modules}, socket) do
    {:ok, assign_modules(socket)}
  end

  def update(
        %{event: :show_module_picker, sequence: sequence, parent_ref: parent_ref, module_set: module_set, type: type} =
          assigns,
        socket
      ) do
    socket
    |> assign(
      show: true,
      sequence: sequence,
      parent_ref: parent_ref,
      type: type,
      module_set: module_set
    )
    |> assign(:collection, Map.get(assigns, :collection, false))
    |> maybe_update_modules_by_filter(assigns)
    |> then(&{:ok, &1})
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def maybe_update_modules_by_filter(socket, %{collection: true, module_set: module_set}) do
    groups =
      module_set
      |> Brando.Content.BlockSlots.modules()
      |> Brando.Utils.split_by(:namespace)
      |> Enum.map(&__MODULE__.sort_namespace/1)

    assign(socket, :modules_by_namespace, groups)
  end

  def maybe_update_modules_by_filter(socket, %{filter: %{parent_id: nil, namespace: _} = filter}) do
    assign(socket, :modules_by_namespace, root_modules_by_namespace(filter))
  end

  def maybe_update_modules_by_filter(socket, %{filter: %{parent_id: parent_id}}) do
    modules = list_picker_modules(%{parent_id: parent_id})

    modules_by_namespace =
      modules
      |> Brando.Utils.split_by(:namespace)
      |> Enum.map(&__MODULE__.sort_namespace/1)

    assign(socket, :modules_by_namespace, modules_by_namespace)
  end

  def maybe_update_modules_by_filter(socket, _assigns) do
    socket
  end

  @doc """
  The modules the picker offers at the root of a block field with
  `module_set`, in the order it lists them: by group, then by each module's
  sequence. Only modules the site has enabled and the set allows.
  """
  def root_modules(module_set) do
    %{parent_id: nil, namespace: module_set}
    |> root_modules_by_namespace()
    |> Enum.flat_map(fn {_translated_namespace, _namespace, modules} -> modules end)
  end

  defp root_modules_by_namespace(%{namespace: set_title} = filter) when set_title != "all" do
    case Brando.Content.get_module_set(%{
           matches: %{title: set_title, filter_modules: filter},
           preload: [module_set_modules: [module: :refs]],
           cache: {:ttl, :infinite}
         }) do
      {:ok, set} ->
        set.module_set_modules
        |> Enum.map(& &1.module)
        |> Brando.Utils.split_by(:namespace)
        |> Enum.map(&__MODULE__.sort_namespace/1)

      {:error, _} ->
        []
    end
  end

  defp root_modules_by_namespace(filter) do
    filter
    |> list_picker_modules()
    |> Brando.Utils.split_by(:namespace)
    |> Enum.map(&__MODULE__.sort_namespace/1)
  end

  def assign_modules(socket) do
    modules = list_picker_modules(%{})

    modules_by_namespace =
      modules
      |> Brando.Utils.split_by(:namespace)
      |> Enum.map(&__MODULE__.sort_namespace/1)

    assign(socket, :modules_by_namespace, modules_by_namespace)
  end

  def handle_event("close_modal", _, socket) do
    module_set = socket.assigns.module_set

    socket
    |> assign(:show, false)
    |> assign(:active_namespace, nil)
    |> assign(:query, "")
    |> assign(:filter, %{parent_id: nil, namespace: module_set})
    |> then(&{:noreply, &1})
  end

  # "" is the "Everything" entry — clearing the filter rather than naming a group.
  def handle_event("toggle_namespace", %{"id" => ""}, socket) do
    {:noreply, assign(socket, :active_namespace, nil)}
  end

  def handle_event("toggle_namespace", %{"id" => namespace}, socket) do
    active_namespace = socket.assigns.active_namespace

    socket
    |> assign(active_namespace: active_namespace != namespace && namespace)
    |> then(&{:noreply, &1})
  end

  # The search field's hook reads the recently used modules from the browser
  # (this user's, on this site) when the picker opens.
  def handle_event("set_recent", %{"ids" => ids}, socket) when is_list(ids) do
    {:noreply, assign(socket, :recent_ids, Enum.filter(ids, &is_binary/1))}
  end

  # Enter inserts on keydown and closes the picker; its keyup still arrives
  # as a search, and must not leave that text in the next picker.
  def handle_event("search", _params, %{assigns: %{show: false}} = socket), do: {:noreply, socket}

  def handle_event("search", %{"value" => query}, socket) do
    {:noreply, assign(socket, :query, query)}
  end

  def handle_event("clear_search", _, socket) do
    {:noreply, assign(socket, :query, "")}
  end

  def handle_event("insert_module", %{"module-id" => module_id}, socket) do
    parent_ref = socket.assigns.parent_ref
    sequence = socket.assigns.sequence
    type = socket.assigns.type

    send_to_ref(parent_ref, %{
      event: "insert_block",
      sequence: sequence,
      module_id: module_id,
      type: type
    })

    socket
    |> assign(:show, false)
    |> assign(:active_namespace, nil)
    |> assign(:query, "")
    |> update(:recent_ids, &remember_recent(&1, module_id))
    |> then(&{:noreply, &1})
  end

  def handle_event("insert_container", _, socket) do
    parent_ref = socket.assigns.parent_ref
    sequence = socket.assigns.sequence

    send_to_ref(parent_ref, %{event: "insert_container", sequence: sequence})
    {:noreply, assign(socket, :show, false)}
  end

  def handle_event("insert_fragment", _, socket) do
    parent_ref = socket.assigns.parent_ref
    sequence = socket.assigns.sequence

    send_to_ref(parent_ref, %{event: "insert_fragment", sequence: sequence})
    {:noreply, assign(socket, :show, false)}
  end

  @doc """
  Returns the `{namespace, modules}` pairs the list shows, filtered by the
  search box within the selected group ("Everything" searches all). Groups
  left empty by the search are dropped.

  The group rail counts the matches in every group, so another group's hits
  stay in view. Without a search, "Everything" starts with the recently used
  modules, which are then left out of their own groups; "Recently used"
  shows only those.
  """
  def visible_groups(assigns) do
    query = String.trim(assigns[:query] || "")
    recent = recent_modules(assigns)

    groups =
      Enum.map(assigns.modules_by_namespace, fn {translated_namespace, _namespace_map, modules} ->
        {presentable_namespace(translated_namespace), modules}
      end)

    groups =
      cond do
        assigns[:active_namespace] == @recent_key ->
          [{gettext("Recently used"), recent}]

        assigns[:active_namespace] ->
          Enum.filter(groups, fn {ns, _} -> ns == assigns.active_namespace end)

        query == "" and recent != [] ->
          recent_refs = MapSet.new(recent, &module_ref/1)

          rest =
            Enum.map(groups, fn {ns, modules} ->
              {ns, Enum.reject(modules, &MapSet.member?(recent_refs, module_ref(&1)))}
            end)

          [{gettext("Recently used"), recent} | rest]

        true ->
          groups
      end

    groups
    |> Enum.map(fn {ns, modules} -> {ns, Enum.filter(modules, &matches?(&1, query))} end)
    |> Enum.reject(fn {_ns, modules} -> modules == [] end)
  end

  # The pick is recorded here as well as in the browser (ModulePickerKeys), the
  # same way. The picker opens with the list it will end up with, so the
  # hook's `set_recent` changes nothing: arriving after the rows had rendered,
  # it used to put "Recently used" on top and move every row under the pointer.
  defp remember_recent(ids, id), do: Enum.take([id | List.delete(ids, id)], @recent_limit * 4)

  # The recently used modules that are in this picker's set, most recent first.
  defp recent_modules(assigns) do
    case Map.get(assigns, :recent_ids, []) do
      [] -> []
      ids -> recent_modules(assigns, ids)
    end
  end

  defp recent_modules(assigns, ids) do
    by_ref =
      for {_, _, modules} <- assigns.modules_by_namespace, module <- modules, into: %{} do
        {module_ref(module), module}
      end

    ids
    |> Enum.flat_map(&List.wrap(by_ref[&1]))
    |> Enum.take(@recent_limit)
  end

  defp module_ref(module), do: Brando.Content.SharedLibrary.encode_reference(module.library_origin, module.id)

  @doc """
  Returns the hero icon name for a module without its own sketch, chosen
  from what it holds as read from its refs. Namespaces are free text, so
  they cannot pick one. Falls back to `"box"`.
  """
  def module_icon(%{datasource: true}), do: "list"
  def module_icon(%{multi: true}), do: "layers"

  def module_icon(%{refs: refs}) when is_list(refs) do
    types = Enum.map(refs, &ref_type/1)

    cond do
      "gallery" in types -> "layout-grid"
      Enum.any?(types, &(&1 in ~w(picture video media))) -> "image"
      "blocks" in types -> "group"
      Enum.any?(types, &(&1 in ~w(text header))) -> "text-align-start"
      true -> "box"
    end
  end

  def module_icon(_module), do: "box"

  defp ref_type(%{data: %{type: type}}) when not is_nil(type), do: to_string(type)
  defp ref_type(_ref), do: nil

  defp presentable_namespace(namespace) when namespace in [nil, ""], do: nil
  defp presentable_namespace(namespace), do: namespace

  defp matches?(_module, ""), do: true

  defp matches?(module, query) do
    haystack = String.downcase("#{translate(module.name)} #{translate(module.help_text)}")
    String.contains?(haystack, String.downcase(query))
  end

  # `Brando.HTML.i18n/1` renders a localised map into markup; the picker also
  # needs it as a plain string, for `aria-label` and for search.
  def translate(nil), do: ""
  def translate(value) when is_binary(value), do: value

  def translate(map) when is_map(map) do
    locale = Gettext.get_locale()
    fallback = Brando.config(:default_language)

    case map[locale] || map[fallback] || map["en"] do
      nil -> ""
      "" -> map["en"] || ""
      translated -> translated
    end
  end

  def sort_namespace({namespace, modules}) do
    sorted_modules = Enum.sort(modules, &(&1.sequence <= &2.sequence))
    current_locale = Gettext.get_locale()
    fallback_locale = Brando.config(:default_language)

    translated_namespace =
      if is_map(namespace) do
        translated_namespace = namespace[current_locale] || namespace[fallback_locale] || ""

        if translated_namespace == "" do
          namespace["en"] || ""
        else
          translated_namespace
        end
      else
        namespace
      end

    {translated_namespace, namespace, sorted_modules}
  end

  defp list_picker_modules(filter) do
    case current_site_and_prefix() do
      {site, prefix} ->
        :module
        |> Brando.Content.SharedLibrary.list_available(site, prefix)
        |> filter_modules(filter)

      nil ->
        {:ok, modules} =
          Brando.Content.list_modules(%{
            filter: filter,
            preload: [:refs],
            cache: {:ttl, :infinite}
          })

        modules
    end
  end

  defp filter_modules(modules, filter) do
    Enum.filter(modules, fn module ->
      Enum.all?(filter, fn
        {:parent_id, value} -> module.parent_id == value
        {:parent_origin, value} -> module.library_origin == normalize_origin(value)
        {:namespace, "all"} -> true
        {:namespace, value} -> module.namespace == value
        _other -> true
      end)
    end)
  end

  defp normalize_origin(origin) when origin in [:shared, "shared"], do: :shared
  defp normalize_origin(_origin), do: :local

  defp current_site_and_prefix do
    with prefix when is_binary(prefix) <- Brando.Tenant.current_prefix(),
         site_key when is_binary(site_key) <- Brando.Tenant.current_site_key(),
         %Brando.Sites.Site{} = site <- Brando.Tenant.Registry.get_site_by_key(site_key) do
      {site, prefix}
    else
      _no_tenant -> nil
    end
  end
end
