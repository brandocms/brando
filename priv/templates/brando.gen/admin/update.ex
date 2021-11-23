defmodule <%= app_module %>Admin.<%= domain %>.<%= Recase.to_pascal(vue_singular) %>UpdateLive do
  use BrandoAdmin.LiveView.Form, schema: <%= schema_module %>
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  import <%= admin_module %>.Gettext

  def render(assigns) do
    ~H"""
    <Content.header
      title={gettext("<%= String.capitalize(plural) %>")}
      subtitle={gettext("Update <%= singular %>")} />

    <.live_component
      module={Form}
      id="<%= singular %>_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}
    />
    """
  end
end
