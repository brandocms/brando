defmodule E2eProjectAdmin.Projects.LockedProjectFormLive do
  @moduledoc "The project's `:locked` form (locked-inputs.spec.js)."
  use BrandoAdmin.LiveView.Form, schema: E2eProject.Projects.Project

  def render(assigns) do
    ~H"""
    <.live_component
      module={BrandoAdmin.Components.Form}
      id="project_form"
      name={:locked}
      entry_id={@entry_id}
      current_user={@current_user}
      presences={@presences}
      schema={@schema}
    />
    """
  end
end
