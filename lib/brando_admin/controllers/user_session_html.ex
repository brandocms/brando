defmodule BrandoAdmin.UserSessionHTML do
  use BrandoAdmin, :html
  import Phoenix.HTML.Form
  import Brando.Gettext

  embed_templates "user_session_html/*"
end
