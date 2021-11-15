defmodule BrandoAdmin.Navigation.MenuCreateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Navigation.Menu
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <Content.header title={gettext("Create menu")} />

    <.live_component module={Form}
      id="menu_form"
      current_user={@current_user}
      schema={@schema}
    />
    """
  end
end
