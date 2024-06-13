defmodule <%= app_module %>Admin.<%= domain %>.<%= camel_singular %>CreateLive do
  use BrandoAdmin.LiveView.Form, schema: <%= inspect schema_module %>
  alias BrandoAdmin.Components.Form
  import <%= admin_module %>.Gettext, warn: false

  def render(assigns) do
    ~H"""
    <.live_component module={Form}
      id="<%= singular %>_form"
      current_user={@current_user}
      schema={@schema}>
      <:header>
        <%%= gettext("Create <%= singular %>") %>
      </:header>
    </.live_component>
    """
  end
end
