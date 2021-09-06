defmodule BrandoAdmin.Components.Form.PolyInputs do
  @moduledoc """
  """
  use Surface.Component
  import BrandoAdmin.Components.Form.Input.Blocks.Utils, only: [inputs_for_poly: 3]

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

  @doc "The code containing the input controls"
  slot default, args: [:form, :index]

  def render(assigns) do
    ~F"""
    <Context
      :for={{f, index}  <- Enum.with_index(inputs_for_poly(@form, @for, @opts))}
      put={Surface.Components.Form, form: f}>
      <#slot :args={form: f, index: index}/>
    </Context>
    """
  end
end
