defmodule BrandoAdmin.Components.Form.FieldBase do
  use BrandoAdmin, :component
  use Phoenix.HTML
  import Phoenix.HTML.Form, only: [input_id: 2]
  import Brando.HTML, only: [render_classes: 1]
  alias BrandoAdmin.Components.Form

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
    relation = Map.get(assigns, :relation, false)
    failed = assigns.form && has_error(assigns.form, assigns.field, relation)
    label = get_label(assigns)
    hidden = label == :hidden

    assigns =
      assigns
      |> assign_new(:header, fn -> nil end)
      |> assign_new(:meta, fn -> nil end)
      |> assign_new(:class, fn -> nil end)
      |> assign(:relation, relation)
      |> assign(:failed, failed)
      |> assign(:hidden, hidden)
      |> assign(:label, label)

    ~H"""
    <div
      class={render_classes(["field-wrapper", @class])}
      id={"#{@form.id}-#{@field}-field-wrapper"}>
      <div class={render_classes(["label-wrapper", hidden: @hidden])}>
        <label
          for={input_id(@form, @field)}
          class={render_classes(["control-label", failed: @failed])}>
          <span><%= @label %></span>
        </label>
        <%= if @form do %>
          <Form.error_tag
            form={@form}
            field={@field}
            relation={@relation}
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

  defp get_label(%{label: nil} = assigns) do
    assigns.field
    |> to_string
    |> Brando.Utils.humanize()
  end

  defp get_label(%{label: label}) do
    label
  end

  defp has_error(form, field, true) do
    field = :"#{field}_id"

    case Keyword.get_values(form.errors, field) do
      [] -> false
      _ -> true
    end
  end

  defp has_error(form, field, _) do
    case Keyword.get_values(form.errors, field) do
      [] -> false
      _ -> true
    end
  end
end
