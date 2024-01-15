defmodule BrandoAdmin.Components.Form.Block do
  use BrandoAdmin, :live_component
  alias BrandoAdmin.Components.Form.Input
  # import Brando.Gettext

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:deleted, fn -> false end)
      |> maybe_assign_children()

    {:ok, socket}
  end

  def maybe_assign_children(%{assigns: %{type: :container, children: children}} = socket) do
    children_forms =
      Enum.map(children, &to_change_form(&1, %{}, socket.assigns.current_user_id))

    socket
    |> stream(:children_forms, children_forms)
  end

  def maybe_assign_children(
        %{assigns: %{type: :module, multi: true, children: children}} = socket
      ) do
    children_forms =
      Enum.map(children, &to_change_form(&1, %{}, socket.assigns.current_user_id))

    socket
    |> stream(:children_forms, children_forms)
  end

  def maybe_assign_children(socket) do
    socket
  end

  def render(%{type: :module, multi: true} = assigns) do
    ~H"""
    <div>
      <h2>MODULE MULTI</h2>
      <%= render_slot(@inner_block) %>
      <div class="form">
        <.form
          for={@form}
          class="mt-1"
          phx-value-id={@form.data.id}
          phx-change="validate_block"
          phx-submit="save_block"
          phx-target={@myself}
        >
          <%= if @belongs_to == :root do %>
            <.inputs_for :let={block} field={@form[:block]}>
              <div class="brando-input">
                <Input.text field={block[:uid]} label="UID" />
                <Input.text field={block[:description]} label="Description" />
              </div>
            </.inputs_for>
          <% else %>
            <div class="brando-input">
              <Input.text field={@form[:uid]} label="UID" />
              <Input.text field={@form[:description]} label="Description" />
            </div>
          <% end %>
        </.form>
      </div>

      <div
        id="blocks-children"
        phx-update="stream"
        phx-hook="Brando.SortableInputsFor"
        data-sortable-id={"sortable-blocks-multi-#{@uid}"}
        data-sortable-handle=".sort-handle"
        data-sortable-selector=".block"
      >
        <div
          :for={{id, child_block_form} <- @streams.children_forms}
          id={id}
          data-id={child_block_form.data.id}
          data-parent_id={child_block_form.data.parent_id}
          class="block draggable"
        >
          <.live_component
            module={__MODULE__}
            id={"#{@id}-blocks-#{id}"}
            uid={child_block_form.data.uid}
            type={child_block_form.data.type}
            multi={child_block_form.data.multi}
            children={child_block_form.data.children}
            parent_id={child_block_form.data.parent_id}
            form={child_block_form}
            current_user_id={@current_user_id}
            belongs_to={:multi}
          >
          </.live_component>
        </div>
      </div>
    </div>
    """
  end

  def render(%{type: :module} = assigns) do
    ~H"""
    <div>
      <h2>MODULE —— belongs to <%= inspect(@belongs_to) %> — deleted: <%= @deleted %></h2>
      <%= render_slot(@inner_block) %>
      <div class="form">
        <.form
          for={@form}
          class="mt-1"
          phx-value-id={@form.data.id}
          phx-change="validate_block"
          phx-submit="save_block"
          phx-target={@myself}
        >
          <.toolbar myself={@myself} />
          <%= if @belongs_to == :root do %>
            <.inputs_for :let={block} field={@form[:block]}>
              <.inputs_for :let={var} field={block[:vars]}>
                <.var var={var} />
              </.inputs_for>
              <div class="brando-input">
                <Input.text field={block[:uid]} label="UID" />
                <Input.text field={block[:description]} label="Description" />
              </div>
            </.inputs_for>
          <% else %>
            <.inputs_for :let={var} field={@form[:vars]}>
              <.var var={var} />
            </.inputs_for>
            <div class="brando-input">
              <Input.text field={@form[:uid]} label="UID" />
              <Input.text field={@form[:description]} label="Description" />
            </div>
          <% end %>
          <%!-- <div>
            <code>
              <pre style="font-size: 9px;font-family: Monospace;"><%= inspect @form, pretty: true %></pre>
            </code>
          </div> --%>
        </.form>
      </div>
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
          <div class="brando-input">
            <.inputs_for :let={block} field={@form[:block]}>
              <Input.text field={block[:uid]} label="UID" />
              <Input.text field={block[:description]} label="Description" />
            </.inputs_for>
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
          :for={{id, child_block_form} <- @streams.children_forms}
          id={id}
          data-id={child_block_form.data.id}
          data-parent_id={child_block_form.data.parent_id}
          class="block draggable"
        >
          <.live_component
            module={__MODULE__}
            id={"#{@id}-blocks-#{id}"}
            uid={child_block_form.data.uid}
            type={child_block_form.data.type}
            multi={child_block_form.data.multi}
            children={child_block_form.data.children}
            parent_id={child_block_form.data.parent_id}
            form={child_block_form}
            current_user_id={@current_user_id}
            belongs_to={:container}
          >
          </.live_component>
        </div>
      </div>
    </div>
    """
  end

  def var(assigns) do
    ~H"""
    <div class="block-var">
      <%= @var.data.key %> - <%= @var.data.type %>
    </div>
    """
  end

  def toolbar(assigns) do
    ~H"""
    <.handle />
    <.delete myself={@myself} />
    """
  end

  def delete(assigns) do
    ~H"""
    <button type="button" phx-click="delete_block" phx-target={@myself}>
      Delete
    </button>
    """
  end

  def handle(assigns) do
    ~H"""
    <div class="sort-handle" data-sortable-group={1}>
      <.icon name="hero-arrows-up-down" />
    </div>
    """
  end

  def handle_event("delete_block", _params, socket) do
    {:noreply, assign(socket, :deleted, true)}
  end

  def handle_event("validate_container", unsigned_params, socket) do
    require Logger

    Logger.error("""

    validate_container:
    #{inspect(unsigned_params, pretty: true)}

    """)

    {:noreply, socket}
  end

  def handle_event("validate_block", unsigned_params, socket) do
    require Logger

    Logger.error("""

    validate_block:
    #{inspect(unsigned_params, pretty: true)}

    """)

    {:noreply, socket}
  end

  defp to_change_form(child_block_or_cs, params, user, action \\ nil) do
    changeset =
      child_block_or_cs
      |> Brando.Content.Block.changeset(params, user)
      |> Map.put(:action, action)

    to_form(changeset,
      as: "child_block",
      id: "child_block_form-#{changeset.data.parent_id}-#{changeset.data.id}"
    )
  end
end
