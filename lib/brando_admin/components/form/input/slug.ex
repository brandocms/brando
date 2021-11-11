defmodule BrandoAdmin.Components.Form.Input.Slug do
  use BrandoAdmin, :component
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.FieldBase

  # prop form, :form
  # prop field, :atom
  # prop label, :string
  # prop placeholder, :string
  # prop instructions, :string
  # prop opts, :list, default: []
  # prop current_user, :map
  # prop uploads, :map

  # data class, :string
  # data monospace, :boolean
  # data disabled, :boolean
  # data debounce, :integer
  # data compact, :boolean
  # data slug_for, :boolean

  def render(assigns) do
    assigns = prepare_input_component(assigns)

    assigns =
      assigns
      |> assign(slug_for: assigns.opts[:for])
      |> assign_new(:data_slug_for, fn -> prepare_slug_for(assigns.form, assigns.opts[:for]) end)

    ~H"""
    <FieldBase.render
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>
      <%= text_input @form, @field,
        class: "text monospace",
        phx_hook: "Brando.Slug",
        phx_debounce: 750,
        data_slug_for: @data_slug_for,
        autocorrect: "off",
        spellcheck: "false" %>
    </FieldBase.render>
    """
  end

  def prepare_slug_for(form, slug_for) when is_list(slug_for) do
    Enum.reduce(slug_for, [], fn sf, acc ->
      acc ++ List.wrap("#{form.id}_#{sf}")
    end)
    |> Enum.join(",")
  end

  def prepare_slug_for(form, slug_for) do
    "#{form.id}_#{slug_for}"
  end
end
