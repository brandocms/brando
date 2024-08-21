defmodule BrandoAdmin.Videos.VideoFormLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Videos.Video
  alias BrandoAdmin.Components.Form
  use Gettext, backend: Brando.Gettext

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="video_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}
    >
      <:header>
        <%= if @live_action == :create do %>
          <%= gettext("Create video") %>
        <% else %>
          <%= gettext("Edit video") %>
        <% end %>
      </:header>
    </.live_component>
    """
  end
end
