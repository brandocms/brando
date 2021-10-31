defmodule BrandoAdmin.Content.PaletteUpdateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Content.Palette
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <Content.header title={gettext("Edit palette")} />

    <Form.live_component
      id="palette_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}
    />
    """
  end
end
