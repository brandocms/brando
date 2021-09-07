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

  def update(assigns, socket) do
    value = input_value(assigns.form, assigns.for)
    # case input_value(assigns.form, assigns.for) do
    #   map when is_map(map) ->
    #     map

    #   list when is_list(list) ->
    #     list
    #     |> Enum.with_index()
    #     |> Enum.map(&{to_string(elem(&1, 1)), elem(&1, 0)})
    #     |> Enum.into(%{})
    #     |> IO.inspect()
    # end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:input_value, value)}
  end

  def render(assigns) do
    ~F"""
    {#if @input_value}
      {#for {index, mv} <- @input_value}
        <#slot :args={
          name: "#{@form.name}[#{@for}][]",
          key: index,
          value: mv
        } />
      {/for}
    {#else}
      No value?
    {/if}
    """
  end
end
