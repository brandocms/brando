defmodule <%= app_module %>Admin.<%= domain %>.<%= camel_singular %>FormLive do
  use BrandoAdmin.LiveView.Form, schema: <%= inspect schema_module %>
  alias BrandoAdmin.Components.Form
  use Gettext, backend: <%= admin_module %>.Gettext, warn: false

  def render(assigns) do
    ~H"""
    <.live_component module={Form}
      id="<%= singular %>_form"
      entry_id={@entry_id}
      current_user={@current_user}
      presences={@presences}
      schema={@schema}>
      <:header>
        <%%= if @live_action == :create do %>
          <%%= gettext("Create <%= singular %>") %>
        <%% else %>
          <%%= gettext("Update <%= singular %>") %>
        <%% end %>
      </:header>
    </.live_component>
    """
  end
end
