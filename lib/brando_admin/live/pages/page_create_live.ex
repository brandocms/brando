defmodule BrandoAdmin.Pages.PageCreateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Pages.Page
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def mount(%{"parent_id" => parent_id, "language" => language}, _session, socket) do
    {:ok,
     socket
     |> assign(:initial_params, %{
       parent_id: parent_id,
       language: language,
       template: "default.html"
     })}
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :initial_params, %{})}
  end

  def render(assigns) do
    ~H"""
    <.live_component module={Form}
      id="page_form"
      current_user={@current_user}
      schema={@schema}
      initial_params={@initial_params}>
      <:header>
        <%= gettext("Create page") %>
      </:header>
    </.live_component>
    """
  end
end
