defmodule BrandoAdmin.Users.UserUpdateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Users.User
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form

  def render(assigns) do
    ~F"""
    <Content.Header
      title="Users"
      subtitle="Update user" />

    <Form
      id="user_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}
    />
    """
  end
end
