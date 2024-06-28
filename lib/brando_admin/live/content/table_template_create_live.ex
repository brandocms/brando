defmodule BrandoAdmin.Content.TableTemplateCreateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Content.TableTemplate
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="table_template_form"
      current_user={@current_user}
      schema={@schema}
    >
      <:header>
        <%= gettext("Create new table template") %>
      </:header>
    </.live_component>
    """
  end
end
