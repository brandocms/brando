defmodule BrandoAdmin.Navigation.MenuUpdateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Navigation.Menu
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <Content.header title={gettext("Edit menu")} />

    <Form.live_component
      id="menu_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}
    />
    """
  end
end
