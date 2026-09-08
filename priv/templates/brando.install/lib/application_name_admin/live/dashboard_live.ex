defmodule <%= application_module %>Admin.DashboardLive do
  use BrandoAdmin.LiveView.Listing, schema: nil
  use Gettext, backend: <%= application_module %>Admin.Gettext
  alias BrandoAdmin.Components.Dashboard

  def render(assigns) do
    assigns = assign_new(assigns, :authorization, fn -> nil end)

    ~H"""
    <.live_component module={Dashboard} id="admin-dashboard" current_user={@current_user} authorization={@authorization} />
    """
  end
end
