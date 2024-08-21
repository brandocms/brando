defmodule BrandoAdmin.Users.UserUpdatePasswordLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Users.User
  alias BrandoAdmin.Components.Form
  use Gettext, backend: Brando.Gettext

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="user_form"
      name={:password}
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}
    >
      <:header>
        <%= gettext("Set initial password") %>
      </:header>
    </.live_component>
    """
  end
end
