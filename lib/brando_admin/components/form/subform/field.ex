defmodule BrandoAdmin.Components.Form.Subform.Field do
  use Surface.Component
  use Phoenix.HTML

  alias BrandoAdmin.Components.Form.Input

  prop input, :map
  prop form, :form
  prop sub_form, :form
  prop uploads, :any
  prop current_user, :any
  prop label, :string
  prop instructions, :string
  prop placeholder, :string
  prop cardinality, :atom

  def render(assigns) do
    ~F"""
    <Input
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
