defmodule BrandoAdmin.Content.ContainerFormLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Content.Container
  alias BrandoAdmin.Components.Form
  use Gettext, backend: Brando.Gettext

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
        <%= if @live_action == :create do %>
          <%= gettext("Create container") %>
        <% else %>
          <%= gettext("Edit container") %>
        <% end %>
      </:header>
    </.live_component>
    """
  end
end
