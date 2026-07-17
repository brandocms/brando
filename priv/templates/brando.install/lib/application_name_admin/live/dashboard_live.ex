defmodule <%= application_module %>Admin.DashboardLive do
  use BrandoAdmin.LiveView.Listing, schema: nil
  use Gettext, backend: <%= application_module %>Admin.Gettext
  alias BrandoAdmin.Components.Content

  def render(assigns) do
    ~H"""
    <Content.header title="Dashboard" subtitle={@current_user.name} />
    """
  end
end
