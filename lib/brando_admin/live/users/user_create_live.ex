defmodule BrandoAdmin.Users.UserCreateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Users.User
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form

  def render(assigns) do
    ~H"""
    <Content.header
      title="Users"
      subtitle="Create user" />

    <.live_component module={Form}
      id="user_form"
      current_user={@current_user}
      schema={@schema}
    />
    """
  end
end
