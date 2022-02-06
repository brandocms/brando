defmodule BrandoAdmin.Navigation.MenuCreateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Navigation.Menu
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <.live_component module={Form}
      id="menu_form"
      current_user={@current_user}
      schema={@schema}>
      <:header>
        <%= gettext("Create menu") %>
      </:header>
    </.live_component>
    """
  end
end
