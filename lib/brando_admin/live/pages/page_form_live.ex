defmodule BrandoAdmin.Pages.PageFormLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Pages.Page
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def mount(
        %{"parent_id" => parent_id, "language" => language},
        _session,
        %{assigns: %{live_action: :create}} = socket
      ) do
    {:ok,
     socket
     |> assign(:initial_params, %{
       parent_id: parent_id,
       language: language,
       template: "default.html"
     })}
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:initial_params, %{})}
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
          <%= gettext("Create page") %>
        <% else %>
          <%= gettext("Edit page") %>
        <% end %>
      </:header>
    </.live_component>
    """
  end
end
