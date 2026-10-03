defmodule BrandoAdmin.Forms.FormFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.Forms.Form
  use Gettext, backend: Brando.Gettext

  def render(assigns) do
    ~H"""
    <div class="admin-workspace settings-workspace form-builder-workspace">
      <.live_component
        module={BrandoAdmin.Components.Form}
        id="form_form"
        entry_id={@entry_id}
        current_user={@current_user}
        schema={@schema}
        initial_params={%{language: @current_user.config.content_language, status: :draft}}
      >
        <:header>
          <%= if @live_action == :create do %>
            {gettext("Create form")}
          <% else %>
            {gettext("Edit form")}
          <% end %>
        </:header>
      </.live_component>
    </div>
    """
  end
end
