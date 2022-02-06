defmodule BrandoAdmin.Users.UserCreateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Users.User
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form

  def render(assigns) do
    ~H"""
    <.live_component module={Form}
      id="user_form"
      current_user={@current_user}
      schema={@schema}>
      <:header>
        <%= gettext("Create user") %>
      </:header>
    </.live_component>
    """
  end
end
