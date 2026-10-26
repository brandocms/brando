defmodule E2eProjectAdmin.Projects.InlineRowFormLive do
  @moduledoc """
  An inline row on its own, which only its `:locked` form opens
  (locked-inputs.spec.js). Routed as an update form, as `mix brando.doctor`
  expects of a Blueprint with a form.
  """
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
