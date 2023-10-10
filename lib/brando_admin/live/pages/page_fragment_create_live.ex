defmodule BrandoAdmin.Pages.PageFragmentCreateLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Pages.Fragment
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  import Brando.Gettext

  def mount(%{"page_id" => page_id, "language" => language}, _session, socket) do
    {:ok, assign(socket, :initial_params, %{page_id: page_id, language: language})}
  end

  def render(assigns) do
    ~H"""
    <Content.header
      title={gettext("Create fragment")} />

    <.live_component module={Form}
      id="fragment_form"
      current_user={@current_user}
      schema={@schema}
      initial_params={@initial_params}
    />
    """
  end
end
