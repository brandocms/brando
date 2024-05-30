defmodule BrandoAdmin.Components.Form.Input.Vars do
  use BrandoAdmin, :live_component
  # use Phoenix.HTML

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input.RenderVar

  import Brando.Gettext
  import BrandoAdmin.Components.Form.Input.Blocks.Utils, only: [inputs_for_poly: 2]

  # prop form, :form
  # prop subform, :form
  # prop field, :atom
  # prop label, :string
  # prop placeholder, :string
  # prop instructions, :string
  # prop opts, :list, default: []
  # prop current_user, :map
  # prop uploads, :map

  def mount(socket) do
    {:ok, socket}
  end

  def update(assigns, socket) do
    empty_subform = Enum.empty?(inputs_for_poly(assigns.field.form[assigns.subform.name], []))

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:empty_subform, empty_subform)}
  end

  def render(assigns) do
    ~H"""
    <fieldset>
      <Form.field_base field={@field} label={@label} instructions={@instructions} class="subform">
        <div id={"#{@field.id}-sortable"} phx-hook="Brando.SubFormSortable">
          <.inputs_for :let={var} field={@field}>
            <div class="subform-entry flex-row" data-id={var.index}>
              <div class="subform-tools">
                <button type="button" class="subform-handle">
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16">
                    <path fill="none" d="M0 0h24v24H0z" /><path
                      class="s"
                      d="M12 2l4.243 4.243-1.415 1.414L12 4.828 9.172 7.657 7.757 6.243 12 2zM2 12l4.243-4.243 1.414 1.415L4.828 12l2.829 2.828-1.414 1.415L2 12zm20 0l-4.243 4.243-1.414-1.415L19.172 12l-2.829-2.828 1.414-1.415L22 12zm-10 2a2 2 0 1 1 0-4 2 2 0 0 1 0 4zm0 8l-4.243-4.243 1.415-1.414L12 19.172l2.828-2.829 1.415 1.414L12 22z"
                      fill="rgba(5,39,82,1)"
                    />
                  </svg>
                </button>
                <button
                  phx-click={JS.push("remove_subentry", target: @myself)}
                  phx-value-index={var.index}
                  type="button"
                  class="subform-delete"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16">
                    <path fill="none" d="M0 0h24v24H0z" /><path
                      class="s"
                      d="M17 6h5v2h-2v13a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V8H2V6h5V3a1 1 0 0 1 1-1h8a1 1 0 0 1 1 1v3zm1 2H6v12h12V8zm-4.586 6l1.768 1.768-1.414 1.414L12 15.414l-1.768 1.768-1.414-1.414L10.586 14l-1.768-1.768 1.414-1.414L12 12.586l1.768-1.768 1.414 1.414L13.414 14zM9 4v2h6V4H9z"
                      fill="rgba(5,39,82,1)"
                    />
                  </svg>
                </button>
              </div>

              <.live_component
                module={RenderVar}
                id={"#{@field.id}-render-var-#{var.index}"}
                var={var}
                render={:all}
                edit
                in_block
              />
            </div>
          </.inputs_for>
        </div>
        <button
          id={"#{@field.id}-add-entry"}
          type="button"
          class="add-entry-button"
          phx-click={JS.push("add_subentry", target: @myself)}
          phx-page-loading
        >
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16">
            <path fill="none" d="M0 0h24v24H0z" /><path
              d="M18 15l-.001 3H21v2h-3.001L18 23h-2l-.001-3H13v-2h2.999L16 15h2zm-7 3v2H3v-2h8zm10-7v2H3v-2h18zm0-7v2H3V4h18z"
              fill="rgba(252,245,243,1)"
            />
          </svg>
          <%= gettext("Add entry") %>
        </button>
      </Form.field_base>
    </fieldset>
    """
  end

  def handle_event("add_subentry", _, socket) do
    changeset = socket.assigns.field.form.source

    default = %Brando.Content.Var{
      type: :string,
      label: "Label",
      key: "key",
      value: "Value",
      important: true
    }

    field_name = socket.assigns.subform.name

    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    current_globals = Ecto.Changeset.get_field(changeset, field_name) || []
    updated_field = current_globals ++ List.wrap(default)
    updated_changeset = Ecto.Changeset.put_change(changeset, field_name, updated_field)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset
    )

    {:noreply, socket}
  end

  def handle_event("remove_subentry", %{"index" => index}, socket) do
    field_name = socket.assigns.subform.name
    changeset = socket.assigns.field.form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    updated_entries =
      changeset
      |> Ecto.Changeset.get_field(field_name, [])
      |> List.delete_at(String.to_integer(index))

    updated_changeset = Ecto.Changeset.put_change(changeset, field_name, updated_entries)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset
    )

    {:noreply, socket}
  end

  def handle_event("force_validate", _, socket) do
    event_id = "#{socket.assigns.field.id}-add-entry"
    {:noreply, push_event(socket, "b:validate:#{event_id}", %{})}
  end

  def handle_event("sequenced_subform", %{"ids" => order_indices}, socket) do
    field_name = socket.assigns.subform.name
    changeset = socket.assigns.field.form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    entries = Ecto.Changeset.get_field(changeset, field_name)
    sorted_entries = Enum.map(order_indices, &Enum.at(entries, &1))

    updated_changeset = Ecto.Changeset.put_change(changeset, field_name, sorted_entries)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset
    )

    {:noreply, socket}
  end
end
