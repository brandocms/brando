defmodule BrandoAdmin.Layouts do
  @moduledoc false
  use BrandoAdmin, :html
  use Gettext, backend: Brando.Gettext

  embed_templates "layouts/*"
end
