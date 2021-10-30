defmodule BrandoAdmin.Components.Form.MapInputs do
  use Surface.Component
  alias BrandoAdmin.Components.Form.Input.Blocks.Utils

  import Phoenix.HTML.Form

  @doc """
  The parent form.
  It should either be a `Phoenix.HTML.Form` emitted by `form_for` or an atom.
  """
  prop form, :form, required: true

  @doc """
  The name of the field related to the child inputs.
  """
  prop for, :atom, required: true

  @doc """
  Extra options for `inputs_for/3`.
  See `Phoenix.HTML.Form.html.inputs_for/4` for the available options.
  """
  prop opts, :keyword, default: []

  data subform, :form
  data input_value, :any

  slot default, args: [:name, :key, :value, :subform]

  def render(assigns) do
    subform = Utils.form_for_map(assigns.form, assigns.for)
    value = input_value(assigns.form, assigns.for)

    assigns =
      assigns
      |> assign(:input_value, value)
      |> assign(:subform, subform)

    ~F"""
    {#for {mk, mv} <- @input_value}
      <#slot :args={name: "#{@form.name}[#{@for}][#{mk}]", key: mk, value: mv, subform: @subform} />
    {/for}
    """
  end
end
