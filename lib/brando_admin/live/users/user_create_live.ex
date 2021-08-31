defmodule BrandoAdmin.Users.UserCreateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Users.User
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input.Surface

  def render(assigns) do
    ~F"""
    <Content.Header
      title="Users"
      subtitle="Create user" />

    <Form
      id="user_form"
      current_user={@current_user}
      schema={@schema}
    />
    """
  end
end
