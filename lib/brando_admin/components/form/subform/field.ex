defmodule BrandoAdmin.Components.Form.Subform.Field do
  use BrandoAdmin, :component
  use Phoenix.HTML

  alias BrandoAdmin.Components.Form.Input

  # prop input, :map
  # prop form, :form
  # prop sub_form, :form
  # prop uploads, :any
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

    ~H"""
    <Input.render
      id={"#{@form.id}-#{@sub_form.id}-input-#{@cardinality}-#{@input.name}"}
      form={@sub_form}
      field={@input.name}
      label={@label}
      instructions={@instructions}
      placeholder={@placeholder}
      uploads={@uploads}
      opts={@input.opts}
      type={@input.type}
      current_user={@current_user} />
    """
  end
end
