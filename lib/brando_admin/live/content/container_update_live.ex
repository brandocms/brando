defmodule BrandoAdmin.Content.ContainerUpdateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Content.Container
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="container_form"
      current_user={@current_user}
      entry_id={@entry_id}
      presences={@presences}
      schema={@schema}
    >
      <:header>
        <%= gettext("Edit container") %>
      </:header>
    </.live_component>
    """
  end
end
