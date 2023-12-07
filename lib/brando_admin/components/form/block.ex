defmodule BrandoAdmin.Components.Form.Block do
  use BrandoAdmin, :live_component
  alias BrandoAdmin.Components.Form.Input
  # import Brando.Gettext

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> maybe_assign_children()

    {:ok, socket}
  end

  def maybe_assign_children(%{assigns: %{type: :container, children: children}} = socket) do
    socket
    |> stream(:children_blocks, children)
  end

  def maybe_assign_children(
        %{assigns: %{type: :module, multi: true, children: children}} = socket
      ) do
    socket
    |> stream(:children_blocks, children)
  end

  def maybe_assign_children(socket) do
    socket
  end

  def render(%{type: :module, multi: true} = assigns) do
    ~H"""
    <div>
      <h2>MODULE MULTI</h2>
      <%= render_slot(@inner_block) %>

      <div
        id="blocks-children"
        phx-update="stream"
        phx-hook="Brando.SortableInputsFor"
        data-sortable-id={"sortable-blocks-multi-#{@uid}"}
        data-sortable-handle=".sort-handle"
        data-sortable-selector=".block"
      >
        <div
          :for={{id, child_block} <- @streams.children_blocks}
          id={id}
          data-id={child_block.id}
          data-parent_id={child_block.parent_id}
          class="block"
        >
          <.live_component
            module={__MODULE__}
            id={"#{@id}-blocks-#{id}"}
            uid={child_block.uid}
            type={child_block.type}
            multi={child_block.multi}
            children={child_block.children}
            parent_id={child_block.parent_id}
            form={nil}
          >
            BLOCK CONTENT: <%= child_block.uid %> -- <%= child_block.type %>
          </.live_component>
        </div>
      </div>
    </div>
    """
  end

  def render(%{type: :module} = assigns) do
    ~H"""
    <div>
      <.handle />
      <h2>MODULE</h2>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  def render(%{type: :container} = assigns) do
    ~H"""
    <div>
      <h2>CONTAINER</h2>
      <%= render_slot(@inner_block) %>
      <div class="form">
        <.form
          for={@form}
          class="mt-1"
          phx-value-id={@form.data.id}
          phx-change="validate_container"
          phx-submit="save_container"
          phx-target={@myself}
        >
          <div>
            <code>
              <pre style="font-size: 9px;font-family: Monospace;"><%= inspect @form, pretty: true %></pre>
            </code>
          </div>

          <div class="brando-input">
            <Input.text field={@form[:uid]} label="UID" />
            <Input.text field={@form[:description]} label="Description" />
          </div>
        </.form>
      </div>

      <div
        id="blocks-children"
        phx-update="stream"
        phx-hook="Brando.SortableInputsFor"
        data-sortable-id="sortable-blocks"
        data-sortable-handle=".sort-handle"
        data-sortable-selector=".block"
      >
        <div
          :for={{id, child_block} <- @streams.children_blocks}
          id={id}
          data-id={child_block.id}
          data-parent_id={child_block.parent_id}
          class="block"
        >
          <.live_component
            module={__MODULE__}
            id={"#{@id}-blocks-#{id}"}
            uid={child_block.uid}
            type={child_block.type}
            multi={child_block.multi}
            children={child_block.children}
            parent_id={child_block.parent_id}
            form={nil}
          >
            BLOCK CONTENT: <%= child_block.uid %> -- <%= child_block.type %>
          </.live_component>
        </div>
      </div>
    </div>
    """
  end

  def handle(assigns) do
    ~H"""
    <div class="sort-handle" data-sortable-group={1}>
      <.icon name="hero-arrows-up-down" />
    </div>
    """
  end

  def handle_event("validate_container", unsigned_params, socket) do
    require Logger

    Logger.error("""

    #{inspect(unsigned_params, pretty: true)}

    """)

    {:noreply, socket}
  end
end
