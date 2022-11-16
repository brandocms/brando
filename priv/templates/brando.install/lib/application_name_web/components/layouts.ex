defmodule <%= application_module %>Web.Layouts do
  use BrandoWeb, :html

  embed_templates "layouts/*"
  embed_templates "partials/*"
end
