defmodule BrandoAdmin.Navigation.MenuFormLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Navigation.Menu
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="menu_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}
    >
      <:header>
        <%= if @live_action == :create do %>
          <%= gettext("Create menu") %>
        <% else %>
          <%= gettext("Edit menu") %>
        <% end %>
      </:header>
    </.live_component>
    """
  end
end
