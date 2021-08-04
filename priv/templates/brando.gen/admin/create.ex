defmodule <%= web_module %>.Admin.<%= Recase.to_pascal(vue_singular) %>CreateLive do
  use BrandoAdmin.LiveView.Listing, schema: <%= schema_module %>
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  import <%= web_module %>.Gettext

  def render(assigns) do
    ~F"""
    <Content.Header
      title={gettext("<%= String.upcase(plural) %>")}
      subtitle={gettext("Create <%= singular %>")}
      instructions="" />

    <Form
      id="<%= singular %>_form"
      current_user={@current_user}
      schema={@schema}
    />
    """
  end
end
