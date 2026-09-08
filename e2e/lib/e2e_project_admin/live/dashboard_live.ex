defmodule E2eProjectAdmin.DashboardLive do
  use BrandoAdmin.LiveView.Listing, schema: nil
  use Gettext, backend: E2eProjectAdmin.Gettext
  alias BrandoAdmin.Components.Dashboard

  def render(assigns) do
    ~H"""
    <.live_component
      module={Dashboard}
      id="admin-dashboard"
      current_user={@current_user}
      authorization={assigns[:authorization]}
    />
    """
  end
end
