defmodule BrandoAdmin.Components.Form.Fieldset do
  use BrandoAdmin.Translator, "forms"
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
    <%= if @fieldset.__struct__ == Brando.Blueprint.Form.Alert do %>
      <.alert type={@fieldset.type}>
        <%= raw(g(@form.source.data.__struct__, @fieldset.content)) %>
      </.alert>
    <% else %>
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
            relations={@relations}
            input={input}
            uploads={@uploads}
            current_user={@current_user} />
        <% end %>
      </fieldset>
    <% end %>
    """
  end
end
