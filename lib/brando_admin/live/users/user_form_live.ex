defmodule BrandoAdmin.Users.UserFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.Users.User
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form

  def render(assigns) do
    ~H"""
    <.live_component module={Form} id="user_form" entry_id={@entry_id} current_user={@current_user} schema={@schema}>
      <:header>
        <%= if @live_action == :create do %>
          {gettext("Create user")}
        <% else %>
          {gettext("Update user")}
        <% end %>
      </:header>
    </.live_component>
    """
  end
end
