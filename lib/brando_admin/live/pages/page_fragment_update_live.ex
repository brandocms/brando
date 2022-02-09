defmodule BrandoAdmin.Pages.PageFragmentUpdateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Pages.Fragment
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <.live_component module={Form}
      id="fragment_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}>
      <:header>
        <%= gettext("Edit fragment") %>
      </:header>
    </.live_component>
    """
  end
end
