defmodule E2eProjectAdmin.Projects.LockedInlineRowFormLive do
  @moduledoc "The inline row's `:locked` form (locked-inputs.spec.js)."
  use BrandoAdmin.LiveView.Form, schema: E2eProject.Projects.InlineRow

  def render(assigns) do
    ~H"""
    <.live_component
      module={BrandoAdmin.Components.Form}
      id="inline_row_form"
      name={:locked}
      entry_id={@entry_id}
      current_user={@current_user}
      presences={@presences}
      schema={@schema}
    />
    """
  end
end
