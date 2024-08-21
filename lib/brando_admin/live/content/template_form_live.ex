defmodule BrandoAdmin.Content.TemplateFormLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Content.Template
  alias BrandoAdmin.Components.Form
  use Gettext, backend: Brando.Gettext

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="template_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}
    >
      <:header>
        <%= if @live_action == :create do %>
          <%= gettext("Create template") %>
        <% else %>
          <%= gettext("Edit template") %>
        <% end %>
      </:header>
    </.live_component>
    """
  end
end
