defmodule BrandoAdmin.Pages.FragmentFormLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Pages.Fragment
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def mount(%{"page_id" => page_id, "language" => language}, _session, socket) do
    if socket.assigns.live_action == :create do
      {:ok, assign(socket, :initial_params, %{page_id: page_id, language: language})}
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
      id="fragment_form"
      entry_id={@entry_id}
      current_user={@current_user}
      initial_params={@initial_params}
      schema={@schema}
    >
      <:header>
        <%= if @live_action == :create do %>
          <%= gettext("Create fragment") %>
        <% else %>
          <%= gettext("Edit fragment") %>
        <% end %>
      </:header>
    </.live_component>
    """
  end
end
