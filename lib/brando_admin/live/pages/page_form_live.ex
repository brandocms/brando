defmodule BrandoAdmin.Pages.PageFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.Pages.Page
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form

  def mount(%{"parent_id" => parent_id, "language" => language}, _session, %{assigns: %{live_action: :create}} = socket) do
    {:ok, assign(socket, :initial_params, %{parent_id: parent_id, language: language, template: "default.html"})}
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :initial_params, %{})}
  end

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="page_form"
      entry_id={@entry_id}
      initial_params={@initial_params}
      presences={@presences}
      current_user={@current_user}
      schema={@schema}
    >
      <:header>
        <%= if @live_action == :create do %>
          {gettext("Create page")}
        <% else %>
          {gettext("Edit page")}
        <% end %>
      </:header>
    </.live_component>
    """
  end
end
