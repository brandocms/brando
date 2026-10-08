defmodule BrandoAdmin.Components.Pages.PageVars do
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

  # data advanced, :boolean

  def mount(socket) do
    {:ok, assign(socket, :advanced, false)}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:row_keys, SubformHelpers.row_keys(assigns.field.form.source, assigns.subform.name))}
  end

  def render(assigns) do
    ~H"""
    <fieldset>
      <Primitives.field_base field={@field} label={@label} instructions={@instructions} class="subform">
        <:header>
          <div class="switch-description">{gettext("Advanced")}</div>
          <div class="brando-input">
            <div>
              <div class="field-base">
                <label
                  class={["switch", "small", @advanced && "toggled"]}
                  phx-click={JS.push("toggle_advanced", target: @myself)}
                >
                  <div class="slider round"></div>
                </label>
              </div>
            </div>
          </div>
        </:header>

        <%= if @advanced do %>
          <div id={"#{@field.id}-sortable"} phx-hook="Brando.SubFormSortable">
            <%= if Enum.empty?(inputs_for_poly(@field, [])) do %>
              <input type="hidden" name={"#{@field.name}"} value="" />
              <div class="subform-empty">&rarr; {gettext("No associated entries")}</div>
            <% end %>
            <Primitives.inputs_for_poly :let={var} field={@field}>
              <div class="subform-entry flex-row" data-id={Enum.at(@row_keys, var.index)}>
                <input
                  :if={SubformHelpers.new_key?(Enum.at(@row_keys, var.index))}
                  type="hidden"
                  name={var[:_key].name}
                  value={Enum.at(@row_keys, var.index)}
                />
                <div class="subform-tools">
                  <button type="button" class="subform-handle">
                    <.icon name="move" />
                  </button>
                  <button
                    phx-click={JS.push("remove_subentry", target: @myself)}
                    phx-value-key={Enum.at(@row_keys, var.index)}
                    type="button"
                    class="subform-delete"
                  >
                    <.icon name="trash" />
                  </button>
                </div>

                <.live_component module={RenderVar} id={"#{@field.id}-render-var-#{var.index}"} var={var} render={:all} edit />
              </div>
            </Primitives.inputs_for_poly>
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
        <% else %>
          <%= unless Enum.empty?(inputs_for_poly(@field, [])) do %>
            <Primitives.inputs_for_poly :let={var} field={@field}>
              <.live_component module={RenderVar} id={"#{@field.id}-render-var-#{var.index}"} var={var} render={:all} />
            </Primitives.inputs_for_poly>
          <% end %>
        <% end %>
      </Primitives.field_base>
    </fieldset>
    """
  end

  def handle_event("toggle_advanced", _, socket) do
    {:noreply, assign(socket, :advanced, !socket.assigns.advanced)}
  end

  def handle_event("add_subentry", _, socket) do
    default = %Brando.Content.Var{
      type: :boolean,
      label: "Label",
      key: "key",
      value: true
    }

    SubformHelpers.append_subentries(socket, default)
  end

  def handle_event("remove_subentry", %{"key" => key}, socket) do
    SubformHelpers.remove_subentry(socket, key)
  end

  def handle_event("force_validate", _, socket) do
    field_name = socket.assigns.subform.name
    event_id = "#{socket.assigns.field.form.id}-#{field_name}-add-entry"
    {:noreply, push_event(socket, "b:validate:#{event_id}", %{})}
  end

  # Was reading `socket.assigns.form.source`, but this component is rendered by
  # `fieldset/field.ex` with a `field=` prop and no `form=` — so that assign does
  # not exist and every drag-reorder raised KeyError, killing the LiveView. The
  # shared helper reads `field.form.source`, which is what the sibling handlers
  # here already use.
  def handle_event("sequenced_subform", %{"ids" => order_indices}, socket) do
    SubformHelpers.sequenced_subform(socket, order_indices)
  end
end
