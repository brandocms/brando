defmodule BrandoAdmin.Content.ContainerCreateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Content.Container
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <.live_component module={Form} id="container_form" current_user={@current_user} schema={@schema}>
      <:header>
        <%= gettext("Create new container") %>
      </:header>
    </.live_component>
    """
  end
end
