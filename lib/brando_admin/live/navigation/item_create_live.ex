defmodule BrandoAdmin.Navigation.ItemCreateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Navigation.Item
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def mount(%{"menu_id" => menu_id, "language" => language}, _session, socket) do
    {:ok, assign(socket, :initial_params, %{menu_id: menu_id, language: language})}
  end

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="item_form"
      current_user={@current_user}
      schema={@schema}
      initial_params={@initial_params}
    >
      <:header>
        <%= gettext("Create item") %>
      </:header>
    </.live_component>
    """
  end
end
