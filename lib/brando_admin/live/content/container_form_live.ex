defmodule BrandoAdmin.Content.ContainerFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.Content.Container
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form

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
          {gettext("Create container")}
        <% else %>
          {gettext("Edit container")}
        <% end %>
      </:header>
    </.live_component>
    """
  end
end
