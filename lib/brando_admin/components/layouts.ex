defmodule BrandoAdmin.Layouts do
  use BrandoAdmin, :html
  embed_templates "layouts/*"

  def csrf_token_value do
    Plug.CSRFProtection.get_csrf_token()
  end

  def csrf_meta_tag(assigns) do
    assigns = assign(assigns, :csrf_token, csrf_token_value())

    ~H"""
    <meta name="csrf-token" content={@csrf_token} />
    """
  end
end
