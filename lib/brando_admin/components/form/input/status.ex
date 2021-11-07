defmodule BrandoAdmin.Components.Form.Input.Status do
  use BrandoAdmin, :component
  use Phoenix.HTML
  import Brando.Gettext
  alias BrandoAdmin.Components.Form.FieldBase
  import BrandoAdmin.Components.Content.List.Row, only: [status_circle: 1]

  # prop form, :form
  # prop field, :atom
  # prop label, :string
  # prop placeholder, :string
  # prop instructions, :string
  # prop opts, :list, default: []
  # prop current_user, :map
  # prop uploads, :map

  # data statuses, :list
  # data class, :string
  # data monospace, :boolean
  # data disabled, :boolean
  # data debounce, :integer
  # data compact, :boolean

  # slot default

  def render(assigns) do
    assigns = prepare_input_component(assigns)

    assigns =
      assigns
      |> assign_new(:statuses, fn ->
        [
          %{value: "draft", label: gettext("Draft")},
          %{value: "pending", label: gettext("Pending")},
          %{value: "published", label: gettext("Published")},
          %{value: "disabled", label: gettext("Deactivated")}
        ]
      end)

    if assigns.compact do
      render_compact(assigns)
    else
      ~H"""
      <FieldBase.render
        form={@form}
        field={@field}
        label={@label}
        instructions={@instructions}
        class={@class}
        compact={@compact}>
        <div class="radios-wrapper status">
          <%= for status <- @statuses do %>
            <div class="form-check">
              <label class="form-check-label">
                <%= radio_button @form, @field, status.value, class: "form-check-input" %>
                <span class={render_classes(["label-text", status.value])}>
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="12"
                    height="12"
                    viewBox="0 0 12 12">
                    <circle
                      class={status.value}
                      r="6"
                      cy="6"
                      cx="6" />
                  </svg>
                  <%= status.label %>
                </span>
              </label>
            </div>
          <% end %>
        </div>
      </FieldBase.render>
      """
    end
  end

  def render_compact(assigns) do
    assigns =
      assigns
      |> prepare_input_component()
      |> assign(:current_status, input_value(assigns.form, assigns.field))
      |> assign(:id, "status-dropdown-#{assigns.form.id}-#{assigns.form.index}-#{assigns.field}")

    ~H"""
    <FieldBase.render
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <div class="radios-wrapper status compact" phx-click={toggle_dropdown("##{@id}")}>
        <.status_circle status={@current_status} publish_at={nil} />
        <div class="status-dropdown hidden" id={@id}>
        <%= for status <- @statuses do %>
          <div class="form-check">
            <label class="form-check-label">
              <%= radio_button @form, @field, status.value, class: "form-check-input" %>
              <span class={render_classes(["label-text", status.value])}>
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  width="12"
                  height="12"
                  viewBox="0 0 12 12">
                  <circle
                    class={status.value}
                    r="6"
                    cy="6"
                    cx="6" />
                </svg>
                <%= status.label %>
              </span>
            </label>
          </div>
        <% end %>
        </div>
      </div>
    </FieldBase.render>
    """
  end
end
