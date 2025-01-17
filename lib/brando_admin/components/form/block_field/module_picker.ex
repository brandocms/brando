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
       modules_by_namespace: []
     )}
  end

  def render(assigns) do
    ~H"""
    <div>
      <Content.modal
        title={gettext("Add content block")}
        id={@id}
        medium
        close={JS.push("close_modal", target: @myself) |> hide_modal("##{@id}")}
      >
        <div :if={@show} class="module-picker-inner">
          <div class="modules-header">
            <div class="module-info">
              {gettext("Select a module")}
            </div>
            <div class="other-buttons">
              <%= if !@hide_fragments do %>
                <button
                  type="button"
                  phx-click={JS.push("insert_fragment", target: @myself) |> hide_modal("##{@id}")}
                >
                  <.icon name="hero-puzzle-piece" />
                  {gettext("Insert fragment")}
                </button>
              <% end %>
              <%= if !@hide_sections do %>
                <button
                  type="button"
                  phx-click={JS.push("insert_container", target: @myself) |> hide_modal("##{@id}")}
                >
                  <.icon name="hero-window" />
                  {gettext("Insert container")}
                </button>
              <% end %>
            </div>
          </div>
          <div class="modules" id={"#{@id}-modules"}>
            <%= for {translated_namespace, namespace_map, modules} <- @modules_by_namespace do %>
              <%= if namespace_map != nil && translated_namespace not in ["", nil] do %>
                <button
                  type="button"
                  class={[
                    "namespace-button",
                    @active_namespace == translated_namespace && "active"
                  ]}
                  phx-click="toggle_namespace"
                  phx-target={@myself}
                  phx-value-id={translated_namespace}
                >
                  <figure>
                    &rarr;
                  </figure>
                  <div class="info">
                    <div class="name">{translated_namespace}</div>
                  </div>
                </button>
                <div class={[
                  "namespace-modules",
                  @active_namespace == translated_namespace && "active"
                ]}>
                  <%= for module <- modules do %>
                    <button
                      type="button"
                      class="module-button"
                      phx-click={JS.push("insert_module", target: @myself) |> hide_modal("##{@id}")}
                      phx-value-module-id={module.id}
                    >
                      <figure class={!module.svg && "empty-preview"}>
                        <%= if module.svg do %>
                          <img src={"data:image/svg+xml;base64,#{module.svg}"} />
                        <% end %>
                      </figure>
                      <div class="info">
                        <div class="name"><.i18n map={module.name} /></div>
                        <div class="instructions"><.i18n map={module.help_text} /></div>
                      </div>
                    </button>
                  <% end %>
                </div>
              <% end %>
            <% end %>
            <%= for {_, namespace_map, modules} <- @modules_by_namespace do %>
              <%= if namespace_map == nil do %>
                <button
                  :for={module <- modules}
                  type="button"
                  class="module-button"
                  phx-click={JS.push("insert_module", target: @myself) |> hide_modal("##{@id}")}
                  phx-value-module-id={module.id}
                >
                  <figure class={!module.svg && "empty-preview"}>
                    {module.svg |> raw}
                  </figure>
                  <div class="info">
                    <div class="name"><.i18n map={module.name} /></div>
                    <div class="instructions"><.i18n map={module.help_text} /></div>
                  </div>
                </button>
              <% end %>
            <% end %>
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
        %{event: :show_module_picker, sequence: sequence, parent_cid: parent_cid, module_set: module_set, type: type} =
          assigns,
        socket
      ) do
    socket
    |> assign(
      show: true,
      sequence: sequence,
      parent_cid: parent_cid,
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
    {:ok, modules} = Brando.Content.list_modules(%{filter: filter})

    modules_by_namespace =
      modules
      |> Brando.Utils.split_by(:namespace)
      |> Enum.map(&__MODULE__.sort_namespace/1)

    assign(socket, :modules_by_namespace, modules_by_namespace)
  end

  def maybe_update_modules_by_filter(socket, %{filter: %{parent_id: parent_id}}) do
    {:ok, modules} = Brando.Content.list_modules(%{filter: %{parent_id: parent_id}})

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
    {:ok, modules} = Brando.Content.list_modules(%{cache: {:ttl, :infinite}})

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
    |> assign(:filter, %{parent_id: nil, namespace: module_set})
    |> then(&{:noreply, &1})
  end

  def handle_event("toggle_namespace", %{"id" => namespace}, socket) do
    active_namespace = socket.assigns.active_namespace

    socket
    |> assign(active_namespace: active_namespace != namespace && namespace)
    |> then(&{:noreply, &1})
  end

  def handle_event("insert_module", %{"module-id" => module_id}, socket) do
    parent_cid = socket.assigns.parent_cid
    sequence = socket.assigns.sequence
    type = socket.assigns.type

    send_update(parent_cid, %{
      event: "insert_block",
      sequence: sequence,
      module_id: module_id,
      type: type
    })

    socket
    |> assign(:show, false)
    |> assign(:active_namespace, nil)
    |> then(&{:noreply, &1})
  end

  def handle_event("insert_container", _, socket) do
    parent_cid = socket.assigns.parent_cid
    sequence = socket.assigns.sequence

    send_update(parent_cid, %{event: "insert_container", sequence: sequence})
    {:noreply, assign(socket, :show, false)}
  end

  def handle_event("insert_fragment", _, socket) do
    parent_cid = socket.assigns.parent_cid
    sequence = socket.assigns.sequence

    send_update(parent_cid, %{event: "insert_fragment", sequence: sequence})
    {:noreply, assign(socket, :show, false)}
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
end
