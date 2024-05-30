defmodule BrandoAdmin.Content.TableTemplateUpdateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Content.TableTemplate
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="table_template_form"
      current_user={@current_user}
      entry_id={@entry_id}
      presences={@presences}
      schema={@schema}
    >
      <:header>
        <%= gettext("Edit template") %>
      </:header>
    </.live_component>
    """
  end
end
