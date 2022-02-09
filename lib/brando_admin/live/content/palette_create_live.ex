defmodule BrandoAdmin.Content.PaletteCreateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Content.Palette
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <.live_component module={Form}
      id="palette_form"
      current_user={@current_user}
      schema={@schema}>
      <:header>
        <%= gettext("Create palette") %>
      </:header>
    </.live_component>
    """
  end
end
