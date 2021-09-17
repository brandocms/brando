defmodule BrandoAdmin.Components.Form.Fieldset do
  use Surface.LiveComponent
  use Phoenix.HTML

  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Subform

  prop current_user, :any
  prop fieldset, :any
  prop form, :any
  prop blueprint, :any
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
        {#if input.__struct__ == Brando.Blueprint.Form.Subform}
          {#if input.component}
            {live_component(@socket, input.component,
              id: "#{@form.id}-#{input.field}-custom-component",
              form: @form,
              subform: input,
              blueprint: @blueprint,
              uploads: @uploads,
              current_user: @current_user,
              opts: []
            )}
          {#else}
            <Subform
              id={"#{@form.id}-subform-#{input.field}"}
              blueprint={@blueprint}
              form={@form}
              uploads={@uploads}
              subform={input}
              current_user={@current_user} />
          {/if}
        {#else}
          <Input
            id={"#{@form.id}-#{input.name}"}
            input={input}
            form={@form}
            blueprint={@blueprint}
            uploads={@uploads}
            current_user={@current_user} />
        {/if}
      {/for}
    </fieldset>
    """
  end
end
