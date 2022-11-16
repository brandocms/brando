defmodule BrandoAdmin.AdminHTML do
  use BrandoAdmin, :html
  import Brando.Gettext
  alias BrandoAdmin.Components.Content

  embed_templates "admin_html/*"
end
