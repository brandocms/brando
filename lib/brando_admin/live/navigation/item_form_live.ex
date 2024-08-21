defmodule BrandoAdmin.Navigation.ItemUpdateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Navigation.Item
  alias BrandoAdmin.Components.Form
  use Gettext, backend: Brando.Gettext

  def mount(%{"menu_id" => menu_id, "language" => language}, _session, socket) do
    if socket.assigns.live_action == :create do
      {:ok, assign(socket, :initial_params, %{menu_id: menu_id, language: language})}
    else
      {:ok, assign(socket, :initial_params, %{})}
    end
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :initial_params, %{})}
  end

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="item_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}
      initial_params={@initial_params}
      presences={@presences}
    >
      <:header>
        <%= if @live_action == :create do %>
          <%= gettext("Create menu item") %>
        <% else %>
          <%= gettext("Edit menu item") %>
        <% end %>
      </:header>
    </.live_component>
    """
  end
end
