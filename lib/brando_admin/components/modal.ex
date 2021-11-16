defmodule BrandoAdmin.Components.Modal do
  use BrandoAdmin, :live_component

  # prop title, :string, required: true
  # prop ok, :event
  # prop close, :event, default: "close_modal"
  # prop center_header, :boolean, default: false
  # prop narrow, :boolean, default: false
  # prop medium, :boolean, default: false
  # prop wide, :boolean, default: false
  # prop remember_scroll_position, :boolean, default: false

  # data action, :atom
  # data show, :boolean, default: false

  # slot default
  # slot header
  # slot footer

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:header, fn -> nil end)
      |> assign_new(:footer, fn -> nil end)
      |> assign_new(:show, fn -> false end)
      |> assign_new(:center_header, fn -> false end)
      |> assign_new(:narrow, fn -> false end)
      |> assign_new(:medium, fn -> false end)
      |> assign_new(:wide, fn -> false end)
      |> assign_new(:remember_scroll_position, fn -> false end)
      |> assign_new(:close, fn -> nil end)
      |> assign_new(:ok, fn -> nil end)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class={render_classes([modal: true, narrow: @narrow, medium: @medium, wide: @wide])}
      phx-window-keydown={hide_modal("##{@id}")}
      phx-key="escape">
      <div class="modal-backdrop" phx-click={hide_modal("##{@id}")} />
      <div class="modal-dialog" role="document">
        <div class="modal-content">
          <header class={render_classes(["modal-header": true, centered: @center_header])}>
            <h2><%= @title %></h2>
            <div class="header-wrap">
              <%= if @header do %>
                <%= render_slot @header %>
              <% end %>
              <button
                type="button"
                class="modal-close"
                phx-click={@close || hide_modal("##{@id}")}>
                <span>&times;</span>
              </button>
            </div>
          </header>
          <section id={"#{@id}-body"} class="modal-body" phx-hook={@remember_scroll_position && "Brando.RememberScrollPosition"}>
            <%= render_slot @inner_block %>
          </section>
          <%= if @footer do %>
            <footer class="modal-footer">
              <%= render_slot @footer %>
              <%= if @ok do %>
                <button class="primary" type="button" phx-click={@ok} phx-value-id={@id}>Ok</button>
              <% end %>
            </footer>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
