defmodule Brando.AdminView do
  # The quoted expression returned by this block is applied
  # to this module and all other views that use this module.
  defmacro __using__(options) do
    root = Dict.fetch! options, :root
    quote do
      use Phoenix.View, root: unquote(root)
      import Plug.Conn, only: [get_session: 2]
      import MyApp.Router.Helpers
      import Brando.Mugshots.Helpers

      # Use Phoenix.HTML to import all HTML functions (forms, tags, etc)
      use Phoenix.HTML

      # Functions defined here are available to all other views/templates
      use Brando.HTML
    end
  end
end