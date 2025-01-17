defmodule BrandoAdmin.Components.Form.Subform.Field do
  @moduledoc false
  use BrandoAdmin, :component
  # use Phoenix.HTML

  alias BrandoAdmin.Components.Form

  # prop input, :map
  # prop sub_form, :form
  # prop parent_uploads, :any
  # prop current_user, :any
  # prop label, :string
  # prop instructions, :string
  # prop placeholder, :string
  # prop cardinality, :atom

  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:label, fn -> nil end)
      |> assign_new(:placeholder, fn -> nil end)
      |> assign_new(:instructions, fn -> nil end)
      |> assign_new(:subform_id, fn -> nil end)

    ~H"""
    <Form.input
      id={"#{@sub_form.id}-input-#{@cardinality}-#{@input.name}"}
      field={@sub_form[@input.name]}
      label={@label}
      instructions={@instructions}
      placeholder={@placeholder}
      parent_uploads={@parent_uploads}
      parent_form_id={@parent_form_id}
      subform_id={@subform_id}
      path={@path}
      opts={@input.opts}
      type={@input.type}
      current_user={@current_user}
    />
    """
  end
end
