defmodule BrandoAdmin.Pages.PageCreateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Pages.Page
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def mount(%{"parent_id" => parent_id, "language" => language}, assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:initial_params, %{parent_id: parent_id, language: language})}
  end

  def mount(_, assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:initial_params, %{})}
  end

  def render(assigns) do
    ~F"""
    <Content.Header title={gettext("Create page")} />

    <Form
      id="page_form"
      current_user={@current_user}
      schema={@schema}
      initial_params={@initial_params}
    />
    """
  end
end
