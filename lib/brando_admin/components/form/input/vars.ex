defmodule BrandoAdmin.Components.Form.Input.Vars do
  @moduledoc false
  use BrandoAdmin, :live_component
  # use Phoenix.HTML
  use Gettext, backend: Brando.Gettext

  import BrandoAdmin.Components.Form.Input.Blocks.Utils, only: [inputs_for_poly: 2]

  alias BrandoAdmin.Components.Form.Input.RenderVar
  alias BrandoAdmin.Components.Form.Input.SubformHelpers
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
    entries = inputs_for_poly(assigns.field.form[assigns.subform.name], [])

    {:ok,
     socket
     |> assign(assigns)
     |> BrandoAdmin.Utils.prepare_subform_component()
     |> assign(:empty_subform, entries == [])
     |> assign(:count, length(entries))}
  end

  # One framed list, like an inline subform's table (SubformTable.css): a
  # line per variable with the grip and insert at the left and a ghost × at
  # the right, and Add entry with the count in the footer. A variable opens in
  # place under its line.
  def render(assigns) do
    ~H"""
    <fieldset>
      <Primitives.field_base field={@field} label={@label} instructions={@instructions} class="subform subform--vars">
        <div id={"#{@field.id}-list"} class="vars-list" phx-hook="Brando.TableRows">
          <div
            id={"#{@field.id}-sortable"}
            class="vars-list-body"
            phx-hook="Brando.SortableInputsFor"
            data-sortable-id={"sortable-#{@field.name}-vars"}
            data-sortable-handle=".subform-handle"
            data-sortable-selector=".subform-entry"
          >
            <.inputs_for :let={var} field={@field} skip_hidden>
              <div class="subform-entry vars-row" data-id={var.index}>
                <input type="hidden" name={var[:id].name} value={var[:id].value} />
                <input type="hidden" name={var[:_persistent_id].name} value={var.index} />
                <input
                  :if={SubformHelpers.new_row_key(var)}
                  type="hidden"
                  name={var[:_key].name}
                  value={SubformHelpers.new_row_key(var)}
                />
                <input type="hidden" name={"#{@field.form.name}[sort_var_ids][]"} value={var.index} />
                <div class="subform-tools">
                  <button
                    type="button"
                    class="subform-insert"
                    aria-label={gettext("Insert variable")}
                    phx-click={
                      JS.push("insert_subentry",
                        value: %{index: var.index, key: SubformHelpers.row_key(var)},
                        target: @myself
                      )
                    }
                  >
                    <.icon name="plus" />
                  </button>
                  <button type="button" class="subform-handle" aria-label={gettext("Reorder variable")}>
                    <.icon name="arrow-up-down" />
                  </button>
                </div>

                <.live_component
                  module={RenderVar}
                  id={"#{@field.id}-render-var-#{var.index}"}
                  var={var}
                  render={:all}
                  form_id={@form_id}
                  edit
                />

                <div class="subform-row-end">
                  <button
                    type="button"
                    class="subform-delete"
                    aria-label={gettext("Delete variable")}
                    name={"#{@field.form.name}[drop_var_ids][]"}
                    value={var.index}
                    phx-click={JS.dispatch("change")}
                  >
                    <.icon name="x" />
                  </button>
                </div>
              </div>
            </.inputs_for>
            <input type="hidden" name={"#{@field.form.name}[drop_var_ids][]"} />
          </div>

          <div class="subform-table-foot">
            <button
              id={"#{@field.id}-add-entry"}
              type="button"
              class="add-entry-button"
              phx-click="add_subentry"
              phx-target={@myself}
            >
              <.icon name="list-plus" />
              {gettext("Add entry")}
            </button>
            <span :if={!@empty_subform} class="subform-table-count">
              {ngettext("1 variable", "%{count} variables", @count)}
            </span>
          </div>
        </div>
      </Primitives.field_base>
    </fieldset>
    """
  end

  def handle_event("focus", _, socket) do
    {:noreply, socket}
  end

  def handle_event("add_subentry", _, socket) do
    SubformHelpers.append_subentries(socket, new_var())
  end

  def handle_event("insert_subentry", %{"index" => index} = params, socket) do
    SubformHelpers.insert_subentry(socket, params["key"], index, new_var())
  end

  def handle_event("remove_subentry", %{"key" => key}, socket) do
    SubformHelpers.remove_subentry(socket, key)
  end

  def handle_event("force_validate", _, socket) do
    event_id = "#{socket.assigns.field.id}-add-entry"
    {:noreply, push_event(socket, "b:validate:#{event_id}", %{})}
  end

  def handle_event("sequenced_subform", %{"ids" => order_indices}, socket) do
    SubformHelpers.sequenced_subform(socket, order_indices)
  end

  defp new_var do
    %Brando.Content.Var{}
    |> Ecto.Changeset.change(%{
      type: :string,
      label: "Label",
      key: "key",
      value: "Value",
      placement: :content
    })
    |> Map.put(:action, :insert)
  end
end
