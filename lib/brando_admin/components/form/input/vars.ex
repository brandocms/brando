defmodule BrandoAdmin.Components.Form.Input.Vars do
  use BrandoAdmin, :live_component
  # use Phoenix.HTML

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input
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
        <div
          id={"#{@field.id}-sortable"}
          phx-hook="Brando.SortableInputsFor"
          data-sortable-id={"sortable-#{@field.name}-vars"}
          data-sortable-handle=".subform-handle"
          data-sortable-selector=".subform-entry"
        >
          <.inputs_for :let={var} field={@field} skip_hidden>
            <div class="subform-entry flex-row" data-id={var.index}>
              <input type="hidden" name={var[:id].name} value={var[:id].value} />
              <input type="hidden" name={var[:_persistent_id].name} value={var.index} />
              <input type="hidden" name={"#{@field.form.name}[sort_var_ids][]"} value={var.index} />
              <div class="subform-tools">
                <button type="button" class="subform-handle">
                  <.icon name="hero-arrows-up-down" />
                </button>
                <button
                  type="button"
                  name={"#{@field.form.name}[drop_var_ids][]"}
                  value={var.index}
                  phx-click={JS.dispatch("change")}
                >
                  <.icon name="hero-x-mark" />
                </button>
              </div>

              <.live_component
                module={RenderVar}
                id={"#{@field.id}-render-var-#{var.index}"}
                var={var}
                render={:all}
                edit
              />
            </div>
          </.inputs_for>
          <input type="hidden" name={"#{@field.form.name}[drop_var_ids][]"} />
        </div>

        <button
          id={"#{@field.id}-add-entry"}
          type="button"
          class="add-entry-button"
          phx-click="add_subentry"
          phx-target={@myself}
        >
          <.icon name="hero-squares-plus" />
          <%= gettext("Add entry") %>
        </button>
      </Form.field_base>
    </fieldset>
    """
  end

  def handle_event("add_subentry", _, socket) do
    changeset = socket.assigns.field.form.source

    new_entry =
      %Brando.Content.Var{}
      |> Ecto.Changeset.change(%{
        type: :string,
        label: "Label",
        key: "key",
        value: "Value",
        important: true
      })
      |> Map.put(:action, :insert)

    field_name = socket.assigns.subform.name

    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    current_globals = Ecto.Changeset.get_field(changeset, field_name) || []
    updated_field = current_globals ++ List.wrap(new_entry)
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
