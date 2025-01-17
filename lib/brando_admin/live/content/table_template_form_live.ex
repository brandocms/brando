defmodule BrandoAdmin.Content.TableTemplateFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.Content.TableTemplate
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="table_template_form"
      current_user={@current_user}
      entry_id={@entry_id}
      presences={@presences}
      schema={@schema}
    >
      <:header>
        <%= if @live_action == :create do %>
          {gettext("Create template")}
        <% else %>
          {gettext("Edit template")}
        <% end %>
      </:header>
    </.live_component>
    """
  end
end
