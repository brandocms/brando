defmodule BrandoAdmin.Images.ImageFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.Images.Image
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form

  def render(assigns) do
    ~H"""
    <.live_component module={Form} id="image_form" entry_id={@entry_id} current_user={@current_user} schema={@schema}>
      <:header>
        <%= if @live_action == :create do %>
          {gettext("Create image")}
        <% else %>
          {gettext("Edit image")}
        <% end %>
      </:header>
    </.live_component>
    """
  end
end
