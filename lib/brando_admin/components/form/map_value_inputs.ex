defmodule BrandoAdmin.Components.Form.MapValueInputs do
  use Surface.Component
  alias BrandoAdmin.Components.Form.Input.Blocks.Utils

  @doc """
  The parent form.
  It should either be a `Phoenix.HTML.Form` emitted by `form_for` or an atom.
  """
  prop form, :form, required: true

  @doc """
  The name of the field related to the child inputs.
  """
  prop for, :any, required: true

  @doc """
  Extra options for `inputs_for/3`.
  See `Phoenix.HTML.Form.html.inputs_for/4` for the available options.
  """
  prop opts, :keyword, default: []

  data subform, :form
  data input_value, :any

  slot default, args: [:name, :key, :value, :subform]

  def render(assigns) do
    subform = Utils.form_for_map_value(assigns.form, assigns.for)
    value = subform.data

    assigns =
      assigns
      |> assign(:input_value, value)
      |> assign(:subform, subform)

    ~F"""
    {#if @input_value}
      {#for {mk, mv} <- @input_value}
        <#slot :args={name: "#{@subform.name}[#{mk}]", key: mk, value: mv, subform: @subform}/>
      {/for}
    {#else}
      No value?
    {/if}
    """
  end
end
