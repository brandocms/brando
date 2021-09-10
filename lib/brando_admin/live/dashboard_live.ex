defmodule BrandoAdmin.DashboardLive do
  use BrandoAdmin.LiveView.Listing, schema: Brando.Users.User
  import Brando.Gettext

  def render(assigns) do
    ~F"""
    <h2>
      {gettext("Hello")}, {@current_user.name}!
    </h2>
    """
  end
end
