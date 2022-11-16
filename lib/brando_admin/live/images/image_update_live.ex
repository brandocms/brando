defmodule BrandoAdmin.Images.ImageUpdateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Images.Image
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <.live_component module={Form}
      id="image_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}>
      <:header>
        <%= gettext("Edit image") %>
      </:header>
    </.live_component>
    """
  end
end
