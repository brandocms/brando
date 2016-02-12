defmodule <%= base %>.<%= scoped %>s.Menu do
  @moduledoc """
  Menu definitions for the <%= scoped %>s Menu.

  See `Brando.Menu` docs for more information.
  Install menu by adding to your `config/brando.exs`

      config :brando, Brando.Menu,
        modules: [<%= base %>.<%= scoped %>s.Menu, ...]

  """
  use Brando.Menu
  import <%= base %>.Backend.Gettext

  menu %{
    name: gettext("<%= scoped %>s"),
    anchor: "<%= plural %>",
    icon: "fa fa-anchor icon",
    submenu: [
      %{name: gettext("Index"), url: {:<%= admin_path %>_path, :index}},
      %{name: gettext("Add"), url: {:<%= admin_path %>_path, :new}, role: :admin}
    ]
  }
end
