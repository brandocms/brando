defmodule <%= admin_module %>View do
  use Brando.Web, :view
  import <%= base %>.Backend.Gettext
  alias <%= admin_module %>Form
end
