defmodule <%= base %>.Web.<%= scoped %>.Menu do
  @moduledoc """
  Menu definitions for the <%= scoped %> Menu.

  See `Brando.Menu` docs for more information.
  Install menu by adding the following to your application's
  initialization code:

        Brando.Registry.register(<%= base %>.<%= scoped %>, [:menu])

  """
  use Brando.Menu
  import <%= base %>.Web.Backend.Gettext

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
