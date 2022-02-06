defmodule BrandoAdmin.Sites.GlobalSetCreateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Sites.GlobalSet
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="global_set_form"
      current_user={@current_user}
      schema={@schema}
      initial_params={%{language: @current_user.config.content_language}}>
      <:header>
        <%= gettext("Create global set") %>
      </:header>
    </.live_component>
    """
  end
end
