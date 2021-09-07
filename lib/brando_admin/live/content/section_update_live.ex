defmodule BrandoAdmin.Content.SectionUpdateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Content.Section
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def render(assigns) do
    ~F"""
    <Content.Header title={gettext("Edit section")} />

    <Form
      id="section_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}
    />
    """
  end
end
