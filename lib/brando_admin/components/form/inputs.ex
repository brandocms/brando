defmodule BrandoAdmin.Components.Form.Inputs do
  @moduledoc """
  A wrapper for `Phoenix.HTML.Form.html.inputs_for/3`.
  """

  use Surface.Component

  import Phoenix.HTML.Form

  @doc """
  The parent form.

  It should either be a `Phoenix.HTML.Form` emitted by `form_for` or an atom.
  """
  prop form, :form

  @doc """
  The name of the field related to the child inputs.
  """
  prop for, :atom

  @doc """
  Extra options for `inputs_for/3`.

  See `Phoenix.HTML.Form.html.inputs_for/4` for the available options.
  """
  prop opts, :keyword, default: []

  @doc "The code containing the input controls"
  slot default, args: [:form, :index]

  def render(assigns) do
    ~F"""
    {#for {f, index} <- Enum.with_index(inputs_for(@form, @for, @opts))}
      <#slot :args={form: f, index: index}/>
    {/for}
    """
  end
end
