defmodule BrandoAdmin.Components.Form.BlockField.ModulePicker do
  use BrandoAdmin, :live_component
  # use Phoenix.HTML
  import Brando.Gettext

  alias BrandoAdmin.Components.Content

  def mount(socket) do
    {:ok, assign(socket, active_namespace: nil, show: false)}
  end

  def update(%{event: :refresh_modules}, socket) do
    require Logger

    Logger.error("""
    ==> REFRESH MODULES
    """)

    {:ok, assign_modules(socket)}
  end

  def update(
        %{
          event: :show_module_picker,
          sequence: sequence,
          parent_cid: parent_cid,
          type: type
        } = assigns,
        socket
      ) do
    socket
    |> assign(show: true, sequence: sequence, parent_cid: parent_cid, type: type)
    |> maybe_update_modules_by_filter(assigns)
    |> then(&{:ok, &1})
  end

  def update(assigns, socket) do
    {:ok, modules} =
      Brando.Content.list_modules(%{
        filter: %{parent_id: nil},
        cache: {:ttl, :infinite}
      })

    {:ok,
     socket
     |> assign(assigns)
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
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  width="24"
                  height="24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M14.25 6.087c0-.355.186-.676.401-.959.221-.29.349-.634.349-1.003 0-1.036-1.007-1.875-2.25-1.875s-2.25.84-2.25 1.875c0 .369.128.713.349 1.003.215.283.401.604.401.959v0a.64.64 0 01-.657.643 48.39 48.39 0 01-4.163-.3c.186 1.613.293 3.25.315 4.907a.656.656 0 01-.658.663v0c-.355 0-.676-.186-.959-.401a1.647 1.647 0 00-1.003-.349c-1.036 0-1.875 1.007-1.875 2.25s.84 2.25 1.875 2.25c.369 0 .713-.128 1.003-.349.283-.215.604-.401.959-.401v0c.31 0 .555.26.532.57a48.039 48.039 0 01-.642 5.056c1.518.19 3.058.309 4.616.354a.64.64 0 00.657-.643v0c0-.355-.186-.676-.401-.959a1.647 1.647 0 01-.349-1.003c0-1.035 1.008-1.875 2.25-1.875 1.243 0 2.25.84 2.25 1.875 0 .369-.128.713-.349 1.003-.215.283-.4.604-.4.959v0c0 .333.277.599.61.58a48.1 48.1 0 005.427-.63 48.05 48.05 0 00.582-4.717.532.532 0 00-.533-.57v0c-.355 0-.676.186-.959.401-.29.221-.634.349-1.003.349-1.035 0-1.875-1.007-1.875-2.25s.84-2.25 1.875-2.25c.37 0 .713.128 1.003.349.283.215.604.401.96.401v0a.656.656 0 00.658-.663 48.422 48.422 0 00-.37-5.36c-1.886.342-3.81.574-5.766.689a.578.578 0 01-.61-.58v0z"
                  />
                </svg>
                <%= gettext("Insert fragment") %>
              </button>
            <% end %>
            <%= if !@hide_sections do %>
              <button type="button" phx-click="insert_container" phx-target={@myself}>
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
                  <path fill="none" d="M0 0h24v24H0z" /><path d="M3 3h18a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zm17 8H4v8h16v-8zm0-2V5H4v4h16zM9 6h2v2H9V6zM5 6h2v2H5V6z" />
                </svg>
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
    {:noreply, assign(socket, :show, false)}
  end

  def handle_event("toggle_namespace", %{"id" => namespace}, socket) do
    active_namespace = socket.assigns.active_namespace
    {:noreply, assign(socket, active_namespace: active_namespace != namespace && namespace)}
  end

  def handle_event("insert_module", %{"module-id" => module_id}, socket) do
    parent_cid = socket.assigns.parent_cid
    sequence = socket.assigns.sequence
    type = socket.assigns.type

    require Logger

    Logger.error("""

    sending update insert_module in ModulePicker to parent_cid: #{inspect(parent_cid, pretty: true)}

    """)

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
    require Logger

    Logger.error("""
    -> Inserting container to parent_cid: #{inspect(parent_cid, pretty: true)}
    """)

    send_update(parent_cid, %{event: "insert_container", sequence: sequence})
    {:noreply, assign(socket, :show, false)}
  end

  def sort_namespace({namespace, modules}) do
    sorted_modules = Enum.sort(modules, &(&1.sequence <= &2.sequence))
    {namespace, sorted_modules}
  end
end
