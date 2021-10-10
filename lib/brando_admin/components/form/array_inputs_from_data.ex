defmodule BrandoAdmin.Components.Form.ArrayInputsFromData do
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
  prop options, :list, required: true

  data checked_values, :list
  slot default, args: [:id, :name, :key, :value, :label, :checked]

  def update(assigns, socket) do
    checked_values = input_value(assigns.form, assigns.for) || []

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:checked_values, Enum.map(checked_values, &to_string(&1)))}
  end

  def render(assigns) do
    ~F"""
    {#for {option, idx} <- Enum.with_index(@options)}
      <#slot :args={
        name: "#{@form.name}[#{@for}][]",
        id: "#{@form.id}-#{@for}-#{idx}",
        key: idx,
        value: option.value,
        label: option.label,
        checked: option.value in @checked_values
      } />
    {/for}
    """
  end
end
