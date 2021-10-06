defmodule BrandoAdmin.Sites.GlobalSetCreateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Sites.GlobalSet
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def render(assigns) do
    ~F"""
    <Content.Header title={gettext("Create global set")} />

    <Form
      id="global_set_form"
      current_user={@current_user}
      schema={@schema}
      initial_params={%{language: @current_user.config.content_language}}
    />
    """
  end
end
