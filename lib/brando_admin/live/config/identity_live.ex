defmodule BrandoAdmin.Sites.IdentityLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Sites.Identity
  alias Brando.Sites
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form

  def mount(_params, assigns, socket) do
    {:ok, identity} = Sites.get_identity()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:entry_id, identity.id)}
  end

  def render(assigns) do
    ~F"""
    <Content.Header
      title="Identity"
      subtitle="Update identity" />

    <Form
      id="identity_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={@schema}
    />
    """
  end
end
