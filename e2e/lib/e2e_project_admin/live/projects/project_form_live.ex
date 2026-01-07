defmodule E2eProjectAdmin.Projects.ProjectFormLive do
  use BrandoAdmin.LiveView.Form, schema: E2eProject.Projects.Project
  alias BrandoAdmin.Components.Form
  use Gettext, backend: E2eProjectAdmin.Gettext, warn: false

  def render(assigns) do
    ~H"""
    <.live_component module={Form}
      id="project_form"
      entry_id={@entry_id}
      current_user={@current_user}
      presences={@presences}
      schema={@schema}>
      <:header>
        <%= if @live_action == :create do %>
          <%= gettext("Create project") %>
        <% else %>
          <%= gettext("Update project") %>
        <% end %>
      </:header>
    </.live_component>
    """
  end
end
