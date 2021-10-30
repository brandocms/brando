defmodule BrandoAdmin.Components.Form.Fieldset do
  use Surface.Component
  use Phoenix.HTML

  alias BrandoAdmin.Components.Form.Fieldset

  prop current_user, :any
  prop fieldset, :any
  prop form, :any
  prop translations, :any
  prop uploads, :any

  def render(assigns) do
    ~F"""
    <fieldset class={
      @fieldset.size,
      "align-end": @fieldset.align == :end,
      inline: @fieldset.style == :inline,
      shaded: @fieldset.shaded
    }>
      {#for input <- @fieldset.fields}
        <Fieldset.Field
          form={@form}
          translations={@translations}
          input={input}
          uploads={@uploads}
          current_user={@current_user} />
      {/for}
    </fieldset>
    """
  end
end
