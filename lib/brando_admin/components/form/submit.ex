defmodule BrandoAdmin.Components.Form.Submit do
  @moduledoc """
  Defines a submit button to send the form.

  All options are forwarded to the underlying `Phoenix.HTML.Form.submit/3`
  """

  use Surface.Component
  use Surface.Components.Events

  import Surface.Components.Utils, only: [events_to_opts: 1, opts_to_attrs: 1]

  @doc "The ID of the form to submit"
  prop form_id, :string

  @doc "The label to be used in the button"
  prop label, :string

  @doc "Class or classes to apply to the button"
  prop class, :css_class

  @doc "If there is image processing happening"
  prop processing, :boolean, required: true

  @doc "Keyword list with options to be passed down to `submit/3`"
  prop opts, :keyword, default: []

  @doc "Slot used for having children other than plain text in the button"
  slot default

  def render(assigns) do
    ~F"""
    <button
      id={"#{@form_id}-submit"}
      type="button"
      disabled={@processing}
      data-processing={@processing}
      data-form-id={@form_id}
      phx-hook="Brando.Submit"
      :attrs={to_attrs(assigns)}>
      <#slot>
        {#if @processing}
          <div class="processing">
            <svg class="spin" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24"><path fill="none" d="M0 0h24v24H0z"/><path d="M5.463 4.433A9.961 9.961 0 0 1 12 2c5.523 0 10 4.477 10 10 0 2.136-.67 4.116-1.81 5.74L17 12h3A8 8 0 0 0 6.46 6.228l-.997-1.795zm13.074 15.134A9.961 9.961 0 0 1 12 22C6.477 22 2 17.523 2 12c0-2.136.67-4.116 1.81-5.74L7 12H4a8 8 0 0 0 13.54 5.772l.997 1.795z"/></svg>
            Processing image(s)
          </div>
        {#else}
          {@label}
        {/if}
      </#slot>
    </button>
    """
  end

  defp to_attrs(assigns) do
    (prop_to_attr_opts(assigns.class, :class) ++ assigns.opts ++ events_to_opts(assigns))
    |> opts_to_attrs()
  end
end
