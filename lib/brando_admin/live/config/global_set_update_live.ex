defmodule BrandoAdmin.Sites.GlobalSetUpdateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Sites.GlobalSet
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def render(assigns) do
    ~F"""
    <Content.Header title={gettext("Edit global set")} />

    <Form
      id="global_set_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}
    />
    """
  end
end
