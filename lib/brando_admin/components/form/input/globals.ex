defmodule BrandoAdmin.Components.Form.Input.Globals do
  @moduledoc false
  use BrandoAdmin, :live_component
  # use Phoenix.HTML
  use Gettext, backend: Brando.Gettext

  import BrandoAdmin.Components.Form.Input.Blocks.Utils, only: [inputs_for_poly: 2]

  alias BrandoAdmin.Components.Form.Input.RenderVar
  alias BrandoAdmin.Components.Form.Primitives

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
      <Primitives.field_base field={@field} label={@label} instructions={@instructions} class="subform">
        <div id={"#{@field.id}-sortable"} phx-hook="Brando.SubFormSortable">
          <%= if Enum.empty?(inputs_for_poly(@field, [])) do %>
            <input type="hidden" name={@field.name} value="" />
            <div class="subform-empty">&rarr; {gettext("No associated entries")}</div>
          <% else %>
            <Primitives.inputs_for_poly :let={var} field={@field}>
              <div class="subform-entry flex-row" data-id={var.index}>
                <div class="subform-tools">
                  <button type="button" class="subform-handle">
                    <.icon name="move" />
                  </button>
                  <button
                    phx-click={JS.push("remove_subentry", target: @myself)}
                    phx-value-index={var.index}
                    type="button"
                    class="subform-delete"
                  >
                    <.icon name="trash" />
                  </button>
                </div>

                <.live_component
                  module={RenderVar}
                  id={"#{@field.id}-render-var-#{var.index}"}
                  var={var}
                  render={:all}
                  form_id={@form_id}
                  edit
                  publish
                />
              </div>
            </Primitives.inputs_for_poly>
          <% end %>
        </div>
        <button
          id={"#{@field.id}-add-entry"}
          type="button"
          class="add-entry-button"
          phx-click={JS.push("add_subentry", target: @myself)}
        >
          <.icon name="list-plus" />
          {gettext("Add entry")}
        </button>
      </Primitives.field_base>
    </fieldset>
    """
  end

  def handle_event("add_subentry", _, socket) do
    changeset = socket.assigns.field.form.source

    default = %Brando.Content.Var{
      type: :boolean,
      label: "Label",
      key: "key",
      value: true
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
    BrandoAdmin.Components.Form.Input.SubformHelpers.remove_subentry(socket, index)
  end

  def handle_event("force_validate", _, socket) do
    event_id = "#{socket.assigns.field.id}-add-entry"
    {:noreply, push_event(socket, "b:validate:#{event_id}", %{})}
  end

  def handle_event("sequenced_subform", %{"ids" => order_indices}, socket) do
    BrandoAdmin.Components.Form.Input.SubformHelpers.sequenced_subform(socket, order_indices)
  end
end
