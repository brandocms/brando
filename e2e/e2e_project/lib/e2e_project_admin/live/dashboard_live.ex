defmodule E2eProjectAdmin.DashboardLive do
  use BrandoAdmin.LiveView.Listing, schema: nil
  use Gettext, backend: E2eProjectAdmin.Gettext
  alias BrandoAdmin.Components.Content

  def render(assigns) do
    ~H"""
    <Content.header title="Dashboard" subtitle={@current_user.name} />
    """
  end
end
