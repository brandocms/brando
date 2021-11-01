defmodule BrandoAdmin.Components.Form.FieldBase do
  use BrandoAdmin, :component
  use Phoenix.HTML
  import Phoenix.HTML.Form, only: [input_id: 2]
  import Brando.HTML, only: [render_classes: 1]
  alias BrandoAdmin.Components.Form.ErrorTag

  # prop form, :form
  # prop field, :any, required: true
  # prop label, :string
  # prop instructions, :string
  # prop class, :string
  # prop compact, :boolean, default: false

  # data failed, :boolean

  # slot default
  # slot meta
  # slot header

  def render(assigns) do
    failed = assigns.form && has_error(assigns.form, assigns.field)
    label = assigns.label || assigns.field |> to_string |> Brando.Utils.humanize()

    assigns =
      assigns
      |> assign_new(:header, fn -> nil end)
      |> assign_new(:meta, fn -> nil end)
      |> assign_new(:class, fn -> nil end)
      |> assign(:failed, failed)
      |> assign(:label, label)

    ~H"""
    <div
      class={render_classes(["field-wrapper", @class])}
      id={"#{@form.id}-#{@field}-field-wrapper"}>
      <div :if={@field} class="label-wrapper">
        <label
          for={input_id(@form, @field)}
          class={render_classes(["control-label", failed: @failed])}>
          <span><%= @label %></span>
        </label>
        <%= if @form do %>
          <ErrorTag.render
            form={@form}
            field={@field}
          />
        <% end %>
        <%= if @header do %>
          <div class="field-wrapper-header">
            <%= render_slot @header %>
          </div>
        <% end %>
      </div>
      <div class="field-base" id={"#{@form.id}-#{@field}-field-base"}>
        <%= render_slot @inner_block %>
      </div>
      <%= if @instructions || @meta do %>
        <div class="meta">
          <%= if @instructions do %>
            <div class="help-text">
              ↳ <span><%= @instructions %></span>
            </div>
            <%= if @meta do %>
              <div class="extra">
                <%= render_slot @meta %>
              </div>
            <% end %>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp has_error(form, field) do
    case Keyword.get_values(form.errors, field) do
      [] -> false
      _ -> true
    end
  end
end
