defmodule BrandoAdmin.Sites.IdentityLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Sites.Identity
  alias Ecto.Changeset
  alias Brando.Users
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Toast

  def render(assigns) do
    schema = @schema

    ~F"""
    <Content.Header
      title="Identity"
      subtitle="Update identity"
      instructions="" />

    <Form
      id="identity_form"
      entry_id={@entry_id}
      current_user={@current_user}
      schema={schema}
    />
    """
  end
end
