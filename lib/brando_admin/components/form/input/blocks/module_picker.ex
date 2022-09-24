defmodule BrandoAdmin.Components.Form.Input.Blocks.ModulePicker do
  use BrandoAdmin, :live_component
  use Phoenix.HTML
  import Brando.Gettext

  alias BrandoAdmin.Components.Content

  # prop insert_block, :event, required: true
  # prop insert_section, :event, required: true
  # prop insert_index, :integer, required: true
  # prop hide_sections, :boolean, default: false

  # data modules_by_namespace, :list
  # data active_namespace, :string

  def mount(socket) do
    {:ok, assign(socket, active_namespace: nil)}
  end

  def update(%{action: :refresh_modules}, socket) do
    {:ok, assign_modules(socket)}
  end

  def update(assigns, socket) do
    {:ok, modules} = Brando.Content.list_modules(%{cache: {:ttl, :infinite}})

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:modules_by_namespace, fn ->
       modules
       |> Brando.Utils.split_by(:namespace)
       |> Enum.map(&__MODULE__.sort_namespace/1)
     end)}
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
      <Content.modal title={gettext "Add content block"} id={@id} medium>
        <div
          class="modules"
          id={"#{@id}-modules"}>
          <%= for {namespace, modules} <- @modules_by_namespace do %>
            <%= unless namespace == "general" do %>
              <button
                type="button"
                class={render_classes(["namespace-button", active: @active_namespace == namespace])}
                phx-click={JS.push("toggle_namespace", target: @myself)}
                phx-value-id={namespace}>
                <figure>
                  &rarr;
                </figure>
                <div class="info">
                  <div class="name"><%= namespace %></div>
                </div>
              </button>
              <div class={render_classes([
                "namespace-modules",
                active: @active_namespace == namespace])}>
                <%= for module <- modules do %>
                  <button
                    type="button"
                    class="module-button"
                    phx-click={@insert_block}
                    phx-value-index={@insert_index}
                    phx-value-module-id={module.id}>
                    <figure>
                      <%= module.svg |> raw %>
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
              <%= for module <- modules do %>
                <button
                  type="button"
                  class="module-button"
                  phx-click={@insert_block}
                  phx-value-index={@insert_index}
                  phx-value-module-id={module.id}>
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
          <% end %>
        </div>
        <%= if !@hide_sections do %>
          <button
            type="button"
            class="btn-stealth"
            phx-click={@insert_section}
            phx-value-index={@insert_index}>
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24"><path fill="none" d="M0 0h24v24H0z"/><path d="M3 3h18a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zm17 8H4v8h16v-8zm0-2V5H4v4h16zM9 6h2v2H9V6zM5 6h2v2H5V6z"/></svg>
            <%= gettext "Insert section" %>
          </button>
        <% end %>
      </Content.modal>
    </div>
    """
  end

  def handle_event(
        "toggle_namespace",
        %{"id" => namespace},
        %{assigns: %{active_namespace: active_namespace}} = socket
      ) do
    {:noreply, assign(socket, active_namespace: active_namespace != namespace && namespace)}
  end

  def sort_namespace({namespace, modules}) do
    sorted_modules = Enum.sort(modules, &(&1.sequence <= &2.sequence))
    {namespace, sorted_modules}
  end
end
