defmodule <%= application_module %>Admin.DashboardLive do
  use BrandoAdmin.LiveView.Listing, schema: nil
  alias BrandoAdmin.Components.Content
  import <%= application_module %>Admin.Gettext

  def render(assigns) do
    ~H"""
    <Content.header title="Dashboard" subtitle={@current_user.name} />
    """
  end
end
