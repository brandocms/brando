defmodule E2eProjectAdmin.Projects.ClientTransformerFormLive do
  use BrandoAdmin.LiveView.Form, schema: E2eProject.Projects.Client

  def render(assigns) do
    ~H"""
    <.live_component
      module={BrandoAdmin.Components.Form}
      id="client_form"
      name={:transformer}
      entry_id={@entry_id}
      current_user={@current_user}
      presences={@presences}
      schema={@schema}
    />
    """
  end
end
