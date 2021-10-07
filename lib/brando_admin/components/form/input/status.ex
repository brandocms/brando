defmodule BrandoAdmin.Components.Form.Input.Status do
  use Surface.Component
  use Phoenix.HTML
  import Brando.Gettext
  alias BrandoAdmin.Components.Form.FieldBase

  prop blueprint, :any
  prop form, :form
  prop field, :any

  data statuses, :list
  data class, :string
  data name, :string

  def update(%{input: %{name: name, opts: opts}} = assigns, socket) do
    {:ok,
     socket
     |> assign_new(:class, fn -> opts[:class] end)
     |> assign_new(:name, fn -> name end)
     |> assign_new(:statuses, fn ->
       [
         %{value: "draft", label: gettext("Draft")},
         %{value: "pending", label: gettext("Pending")},
         %{value: "published", label: gettext("Published")},
         %{value: "disabled", label: gettext("Deactivated")}
       ]
     end)
     |> assign(assigns)}
  end

  def render(assigns) do
    ~F"""
    <FieldBase
      blueprint={@blueprint}
      form={@form}
      class={@class}
      field={@name}>
      <div class="radios-wrapper status">
        <div
          :for={status <- @statuses}
          class="form-check">
          <label class="form-check-label">
            {radio_button @form, @name, status.value, class: "form-check-input"}
            <span class={"label-text", status.value}>
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
              {status.label}
            </span>
          </label>
        </div>
      </div>
    </FieldBase>
    """
  end
end
