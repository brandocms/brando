defmodule BrandoAdmin.Content.TemplateUpdateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Content.Template
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def render(assigns) do
    ~F"""
    <Content.Header title={gettext("Edit template")} />

    <Form
      id="template_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}
    />
    """
  end
end
