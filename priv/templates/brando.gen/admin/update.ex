defmodule <%= app_module %>Admin.<%= domain %>.<%= Recase.to_pascal(vue_singular) %>UpdateLive do
  use BrandoAdmin.LiveView.Form, schema: <%= inspect schema_module %>
  alias BrandoAdmin.Components.Form
  import <%= admin_module %>.Gettext

  def render(assigns) do
    ~H"""
    <.live_component module={Form}
      id="<%= singular %>_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}>
      <:header>
        <%%= gettext("Update <%= singular %>") %>
      </:header>
    </.live_component>
    """
  end
end
