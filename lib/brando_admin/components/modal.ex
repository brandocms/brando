defmodule BrandoAdmin.Components.Modal do
  use Surface.LiveComponent

  prop title, :string, required: true
  prop ok, :event
  prop close, :event, default: "close_modal"
  prop center_header, :boolean, default: false
  prop narrow, :boolean, default: false
  prop medium, :boolean, default: false
  prop wide, :boolean, default: false
  prop remember_scroll_position, :boolean, default: false

  data action, :atom
  data show, :boolean, default: false

  slot default
  slot header
  slot footer

  def update(%{id: id} = assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      case assigns[:action] do
        nil ->
          socket

        :show ->
          socket
          |> assign(:show, true)
          |> push_event("b:modal:show:#{id}", %{})

        :hide ->
          socket
          |> assign(:show, false)
          |> push_event("b:modal:hide:#{id}", %{})
      end
      |> assign(:action, nil)

    {:ok, socket}
  end

  def render(assigns) do
    ~F"""
    <div
      id={@id}
      class={"modal", narrow: @narrow, medium: @medium, wide: @wide}
      phx-key="Escape"
      data-b-modal={@show && "show" || "hide"}
      phx-hook="Brando.Modal"
      :on-window-keydown={@close}>
      <div class="modal-backdrop" />
      <div class="modal-dialog" role="document">
        <div class="modal-content">
          <header class={"modal-header", centered: @center_header}>
            <h2>{@title}</h2>
            <div class="header-wrap">
              <#slot name="header" />
              <button
                type="button"
                class="modal-close"
                :on-click={@close}>
                &times;
              </button>
            </div>
          </header>
          <section id={"#{@id}-body"} class="modal-body" phx-hook={@remember_scroll_position && "Brando.RememberScrollPosition"}>
            <#slot />
          </section>
          {#if slot_assigned?(:footer)}
            <footer class="modal-footer">
              <#slot name="footer">
                {#if @ok}
                  <button class="primary" type="button" :on-click={@ok} phx-value-id={@id}>Ok</button>
                {/if}
              </#slot>
            </footer>
          {/if}
        </div>
      </div>
    </div>
    """
  end

  # Public API
  def show(id) do
    send_update(__MODULE__, id: id, action: :show)
  end

  def hide(id) do
    send_update(__MODULE__, id: id, action: :hide)
  end

  def handle_event("close_modal", _params, %{assigns: %{id: id}} = socket) do
    hide(id)
    {:noreply, socket}
  end
end
