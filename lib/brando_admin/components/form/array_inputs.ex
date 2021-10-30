defmodule BrandoAdmin.Components.Form.ArrayInputs do
  use Surface.Component
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
  data input_value, :any
  slot default, args: [:name, :key, :value]

  def render(assigns) do
    value = input_value(assigns.form, assigns.for)
    assigns = assign(assigns, :input_value, value)

    ~F"""
    {#if @input_value}
      {#for {mv, idx} <- Enum.with_index(@input_value)}
        <#slot :args={
          name: "#{@form.name}[#{@for}][]",
          key: idx,
          value: mv
        } />
      {/for}
    {#else}
      No value?
    {/if}
    """
  end
end
