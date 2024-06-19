defmodule BrandoAdmin.Navigation.ItemUpdateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Navigation.Item
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="item_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}
      presences={@presences}
    >
      <:header>
        <%= gettext("Edit menu item") %>
      </:header>
    </.live_component>
    """
  end
end
