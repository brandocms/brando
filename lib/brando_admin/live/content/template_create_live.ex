defmodule BrandoAdmin.Content.TemplateCreateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Content.Template
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <Content.header title={gettext("Create template")} />

    <Form.live_component
      id="template_form"
      current_user={@current_user}
      schema={@schema}
    />
    """
  end
end
