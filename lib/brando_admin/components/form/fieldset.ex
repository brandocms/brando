defmodule BrandoAdmin.Components.Form.Fieldset do
  use BrandoAdmin, :component
  use Phoenix.HTML

  alias BrandoAdmin.Components.Form.Fieldset

  # prop current_user, :any
  # prop fieldset, :any
  # prop form, :any
  # prop translations, :any
  # prop uploads, :any

  def render(assigns) do
    ~H"""
    <fieldset class={render_classes([
      @fieldset.size,
      "align-end": @fieldset.align == :end,
      inline: @fieldset.style == :inline,
      shaded: @fieldset.shaded
    ])}>
      <%= for input <- @fieldset.fields do %>
        <Fieldset.Field.render
          form={@form}
          translations={@translations}
          input={input}
          uploads={@uploads}
          current_user={@current_user} />
      <% end %>
    </fieldset>
    """
  end
end
