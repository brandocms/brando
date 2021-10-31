defmodule BrandoAdmin.Pages.PageFragmentUpdateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Pages.Fragment
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <Content.header
      title={gettext("Edit fragment")} />

    <Form.live_component
      id="fragment_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}
    />
    """
  end
end
