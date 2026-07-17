defmodule BrandoAdmin.Content.ModuleSetFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.Content.ModuleSet
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="module_set_form"
      entry_id={@entry_id}
      current_user={@current_user}
      presences={@presences}
      schema={@schema}
    >
      <:header>
        <%= if @live_action == :create do %>
          {gettext("Create module set")}
        <% else %>
          {gettext("Edit module set")}
        <% end %>
      </:header>
    </.live_component>
    """
  end
end
