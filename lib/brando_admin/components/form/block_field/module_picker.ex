defmodule BrandoAdmin.Components.Form.BlockField.ModulePicker do
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext
  alias BrandoAdmin.Components.Content

  def mount(socket) do
    {:ok, assign(socket, active_namespace: nil, module_namespace: "all", show: false)}
  end

  def update(%{event: :refresh_modules}, socket) do
    {:ok, assign_modules(socket)}
  end

  def update(
        %{
          event: :show_module_picker,
          sequence: sequence,
          parent_cid: parent_cid,
          module_namespace: module_namespace,
          type: type
        } = assigns,
        socket
      ) do
    socket
    |> assign(
      show: true,
      sequence: sequence,
      parent_cid: parent_cid,
      type: type,
      module_namespace: module_namespace
    )
    |> maybe_update_modules_by_filter(assigns)
    |> then(&{:ok, &1})
  end

  def update(assigns, socket) do
    module_namespace = socket.assigns.module_namespace

    {:ok, modules} =
      Brando.Content.list_modules(%{
        filter: %{parent_id: nil, namespace: module_namespace},
        cache: {:ttl, :infinite}
      })

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:filter, %{parent_id: nil, namespace: module_namespace})
     |> assign_new(:modules_by_namespace, fn ->
       modules
       |> Brando.Utils.split_by(:namespace)
       |> Enum.map(&__MODULE__.sort_namespace/1)
     end)}
  end

  def maybe_update_modules_by_filter(socket, %{filter: filter}) do
    {:ok, modules} = Brando.Content.list_modules(%{filter: filter})

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

  def render(assigns) do
    ~H"""
    <div>
      <Content.modal
        title={gettext("Add content block")}
        id={@id}
        show={@show}
        medium
        close={JS.push("close_modal", target: @myself)}
      >
        <div class="modules-header">
          <div class="module-info">
            <%= gettext("Select a module") %>
          </div>
          <div class="other-buttons">
            <%= if !@hide_fragments do %>
              <button type="button" phx-click="insert_fragment" phx-target={@myself}>
                <.icon name="hero-puzzle-piece" />
                <%= gettext("Insert fragment") %>
              </button>
            <% end %>
            <%= if !@hide_sections do %>
              <button type="button" phx-click="insert_container" phx-target={@myself}>
                <.icon name="hero-window" />
                <%= gettext("Insert container") %>
              </button>
            <% end %>
          </div>
        </div>
        <div class="modules" id={"#{@id}-modules"}>
          <%= for {namespace, modules} <- @modules_by_namespace do %>
            <%= unless namespace == "general" do %>
              <button
                type="button"
                class={[
                  "namespace-button",
                  @active_namespace == namespace && "active"
                ]}
                phx-click="toggle_namespace"
                phx-target={@myself}
                phx-value-id={namespace}
              >
                <figure>
                  &rarr;
                </figure>
                <div class="info">
                  <div class="name"><%= namespace %></div>
                </div>
              </button>
              <div class={[
                "namespace-modules",
                @active_namespace == namespace && "active"
              ]}>
                <%= for module <- modules do %>
                  <button
                    type="button"
                    class="module-button"
                    phx-click="insert_module"
                    phx-target={@myself}
                    phx-value-module-id={module.id}
                  >
                    <figure>
                      <%= if module.svg do %>
                        <img src={"data:image/svg+xml;base64,#{module.svg}"} />
                      <% end %>
                    </figure>
                    <div class="info">
                      <div class="name"><%= module.name %></div>
                      <div class="instructions"><%= module.help_text %></div>
                    </div>
                  </button>
                <% end %>
              </div>
            <% end %>
          <% end %>
          <%= for {namespace, modules} <- @modules_by_namespace do %>
            <%= if namespace == "general" do %>
              <button
                :for={module <- modules}
                type="button"
                class="module-button"
                phx-click="insert_module"
                phx-target={@myself}
                phx-value-module-id={module.id}
              >
                <figure>
                  <%= module.svg |> raw %>
                </figure>
                <div class="info">
                  <div class="name"><%= module.name %></div>
                  <div class="instructions"><%= module.help_text %></div>
                </div>
              </button>
            <% end %>
          <% end %>
        </div>
      </Content.modal>
    </div>
    """
  end

  def handle_event("close_modal", _, socket) do
    module_namespace = socket.assigns.module_namespace

    {:noreply,
     socket
     |> assign(:show, false)
     |> assign(:filter, %{parent_id: nil, namespace: module_namespace})}
  end

  def handle_event("toggle_namespace", %{"id" => namespace}, socket) do
    active_namespace = socket.assigns.active_namespace
    {:noreply, assign(socket, active_namespace: active_namespace != namespace && namespace)}
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

    {:noreply, assign(socket, :show, false)}
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
    {namespace, sorted_modules}
  end
end
