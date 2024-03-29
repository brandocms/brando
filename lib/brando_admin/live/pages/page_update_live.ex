defmodule BrandoAdmin.Pages.PageUpdateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Pages.Page
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <.live_component module={Form}
      id="page_form"
      entry_id={@entry_id}
      current_user={@current_user}
      presences={@presences}
      schema={@schema}>
      <:header>
        <%= gettext("Edit page") %>
      </:header>
    </.live_component>
    """
  end
end
