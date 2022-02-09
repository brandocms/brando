defmodule BrandoAdmin.Sites.GlobalSetUpdateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Sites.GlobalSet
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <.live_component module={Form}
      id="global_set_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}>
      <:header>
        <%= gettext("Edit global set") %>
      </:header>
    </.live_component>
    """
  end
end
