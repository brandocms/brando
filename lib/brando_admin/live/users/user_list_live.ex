defmodule BrandoAdmin.Users.UserListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Users.User
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content

  def render(assigns) do
    ~H"""
    <Content.header title={gettext("Users")} subtitle={gettext("Overview")}>
      <.link navigate="/admin/users/create" class="primary">
        {gettext("Create new")}
      </.link>
    </Content.header>

    <.live_component
      module={Content.List}
      id={"content_listing_#{@schema}_default"}
      schema={@schema}
      current_user={@current_user}
      uri={@uri}
      params={@params}
      listing={:default}
    />
    """
  end

  def handle_event("disable_user", %{"id" => id}, socket) do
    user = Brando.Users.get_user!(id)
    Brando.Users.set_active(id, false, user)
    send(self(), {:toast, gettext("User disabled.")})
    {:noreply, socket}
  end

  def handle_event("enable_user", %{"id" => id}, socket) do
    user = Brando.Users.get_user!(id)
    Brando.Users.set_active(id, true, user)
    send(self(), {:toast, gettext("User enabled.")})
    {:noreply, socket}
  end
end
