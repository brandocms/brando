defmodule BrandoAdmin.Content.PaletteFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.Content.Palette
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="palette_form"
      entry_id={@entry_id}
      current_user={@current_user}
      presences={@presences}
      schema={@schema}
    >
      <:header>
        <%= if @live_action == :create do %>
          {gettext("Create palette")}
        <% else %>
          {gettext("Edit palette")}
        <% end %>
      </:header>
    </.live_component>
    """
  end
end
