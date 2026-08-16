defmodule BrandoAdmin.Components.Form.BlockField.ModulePicker do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content

  def mount(socket) do
    {:ok,
     assign(socket,
       active_namespace: nil,
       module_set: "all",
       show: false,
       query: "",
       modules_by_namespace: []
     )}
  end

  def render(assigns) do
    groups = visible_groups(assigns)

    # Counts come from the unfiltered set so the sidebar stays a stable map of
    # what exists, rather than flickering as you type.
    namespace_counts =
      for {translated_namespace, _map, modules} <- assigns.modules_by_namespace,
          translated_namespace not in [nil, ""],
          do: {translated_namespace, length(modules)}

    total_count =
      Enum.reduce(assigns.modules_by_namespace, 0, fn {_, _, modules}, acc -> acc + length(modules) end)

    assigns =
      assigns
      |> assign(:groups, groups)
      |> assign(:namespace_counts, namespace_counts)
      |> assign(:total_count, total_count)

    ~H"""
    <div>
      <Content.modal
        title={gettext("Add content block")}
        id={@id}
        wide
        close={JS.push("close_modal", target: @myself) |> hide_modal("##{@id}")}
      >
        <:header :if={@show and (!@hide_fragments or !@hide_sections)}>
          <div class="module-picker-extras">
            <span class="module-picker-extras-label">{gettext("Or insert")}</span>
            <button
              :if={!@hide_sections}
              type="button"
              phx-click={JS.push("insert_container", target: @myself) |> hide_modal("##{@id}")}
            >
              <.icon name="hero-window" />
              {gettext("Container")}
            </button>
            <button
              :if={!@hide_fragments}
              type="button"
              phx-click={JS.push("insert_fragment", target: @myself) |> hide_modal("##{@id}")}
            >
              <.icon name="hero-puzzle-piece" />
              {gettext("Fragment")}
            </button>
          </div>
        </:header>
        <div :if={@show} class="module-picker">
          <div class="module-picker-search">
            <.icon name="hero-magnifying-glass" />
            <input
              type="text"
              name="q"
              value={@query}
              phx-keyup="search"
              phx-target={@myself}
              phx-debounce="120"
              phx-mounted={JS.focus()}
              autocomplete="off"
              spellcheck="false"
              placeholder={gettext("Search modules")}
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
              <.icon name="hero-x-mark" />
            </button>
          </div>

          <div class="module-picker-body">
            <nav
              :if={@namespace_counts != []}
              class={["module-picker-namespaces", @query != "" && "is-searching"]}
              aria-label={gettext("Module groups")}
            >
              <button
                type="button"
                class={["module-picker-namespace", (@query == "" and is_nil(@active_namespace)) && "active"]}
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
                class={["module-picker-namespace", (@query == "" and @active_namespace == namespace) && "active"]}
                phx-click="toggle_namespace"
                phx-target={@myself}
                phx-value-id={namespace}
              >
                <span class="label">{namespace}</span>
                <span class="count">{count}</span>
              </button>
            </nav>

            <div class="module-picker-results">
              <section :for={{namespace, modules} <- @groups} :key={namespace || "-"} class="module-picker-group">
                <h3 :if={namespace not in [nil, ""]} class="module-picker-group-title">{namespace}</h3>
                <div class="module-picker-grid">
                  <button
                    :for={module <- modules}
                    :key={{module.library_origin, module.id}}
                    type="button"
                    class={["module-card", module.svg && "has-preview"]}
                    data-color={module.color}
                    aria-label={translate(module.name)}
                    phx-click={JS.push("insert_module", target: @myself) |> hide_modal("##{@id}")}
                    phx-value-module-id={Brando.Content.SharedLibrary.encode_reference(module.library_origin, module.id)}
                  >
                    <%!-- Only modules that actually ship an SVG get a preview
                          box. Rendering an empty 16:9 placeholder for the rest
                          made every card mostly dead space, which is the common
                          case — most modules have no svg. --%>
                    <figure :if={module.svg} class="module-card-preview">
                      <img src={"data:image/svg+xml;base64,#{module.svg}"} alt="" />
                    </figure>
                    <span class="module-card-body">
                      <span class="module-card-name">{translate(module.name)}</span>
                      <span class="badge">
                        <%= cond do %>
                          <% module.library_origin == :shared and module.source_module_id -> %>
                            {gettext("customized")}
                          <% module.library_origin == :shared -> %>
                            {gettext("shared")}
                          <% true -> %>
                            {gettext("site")}
                        <% end %>
                      </span>
                      <span :if={module.update_available} class="badge warning">
                        {gettext("update available")}
                      </span>
                      <span :if={translate(module.help_text) != ""} class="module-card-help">
                        {translate(module.help_text)}
                      </span>
                    </span>
                  </button>
                </div>
              </section>

              <p :if={@groups == []} class="module-picker-empty">
                {gettext("No modules match \"%{query}\"", query: @query)}
              </p>
            </div>
          </div>
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
    |> maybe_update_modules_by_filter(assigns)
    |> then(&{:ok, &1})
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def maybe_update_modules_by_filter(socket, %{filter: %{parent_id: nil, namespace: set_title} = filter})
      when set_title != "all" do
    {:ok, set} =
      Brando.Content.get_module_set(%{
        matches: %{title: set_title, filter_modules: filter},
        preload: [module_set_modules: :module],
        cache: {:ttl, :infinite}
      })

    modules = Enum.map(set.module_set_modules, & &1.module)

    modules_by_namespace =
      modules
      |> Brando.Utils.split_by(:namespace)
      |> Enum.map(&__MODULE__.sort_namespace/1)

    assign(socket, :modules_by_namespace, modules_by_namespace)
  end

  def maybe_update_modules_by_filter(socket, %{filter: %{parent_id: nil, namespace: _} = filter}) do
    modules = list_picker_modules(filter)

    modules_by_namespace =
      modules
      |> Brando.Utils.split_by(:namespace)
      |> Enum.map(&__MODULE__.sort_namespace/1)

    assign(socket, :modules_by_namespace, modules_by_namespace)
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

  @doc false
  # What the grid shows: `{namespace, modules}` pairs, already filtered by the
  # search box and the selected group. Searching deliberately ignores the group
  # selection — typing a name you remember should find it wherever it lives.
  def visible_groups(assigns) do
    query = String.trim(assigns[:query] || "")

    assigns.modules_by_namespace
    |> Enum.map(fn {translated_namespace, _namespace_map, modules} ->
      {presentable_namespace(translated_namespace), modules}
    end)
    |> then(fn groups ->
      if query == "" and assigns[:active_namespace],
        do: Enum.filter(groups, fn {ns, _} -> ns == assigns.active_namespace end),
        else: groups
    end)
    |> Enum.map(fn {ns, modules} -> {ns, Enum.filter(modules, &matches?(&1, query))} end)
    |> Enum.reject(fn {_ns, modules} -> modules == [] end)
  end

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
