defmodule BrandoAdmin.Pages.PageFragmentCreateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Pages.Fragment
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def mount(%{"page_id" => page_id, "language" => language}, assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:initial_params, %{page_id: page_id, language: language})}
  end

  def render(assigns) do
    ~F"""
    <Content.Header
      title={gettext("Create fragment")} />

    <Form
      id="fragment_form"
      current_user={@current_user}
      schema={@schema}
      initial_params={@initial_params}
    />
    """
  end
end
