defmodule BrandoAdmin.Users.UserUpdateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Users.User
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <Content.header
      title={gettext "Users"}
      subtitle={gettext "Update user"} />

    <.live_component module={Form}
      id="user_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}
    />
    """
  end
end
