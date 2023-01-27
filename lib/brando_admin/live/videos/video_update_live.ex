defmodule BrandoAdmin.Videos.VideoUpdateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Videos.Video
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <.live_component module={Form}
      id="video_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}>
      <:header>
        <%= gettext("Edit video") %>
      </:header>
    </.live_component>
    """
  end
end
