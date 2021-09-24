defmodule BrandoAdmin.Sites.SEOLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Sites.SEO
  alias Brando.Sites
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form

  def mount(_params, assigns, socket) do
    {:ok, seo} = Sites.get_seo()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:entry_id, seo.id)}
  end

  def render(assigns) do
    ~F"""
    <Content.Header
      title="SEO"
      subtitle="Update SEO" />

    <Form
      id="seo_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}
    />
    """
  end
end
