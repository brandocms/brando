defmodule Brando.AdminView do
  # The quoted expression returned by this block is applied
  # to this module and all other views that use this module.
  defmacro __using__(options) do
    root = Dict.fetch! options, :root
    quote do
      use Phoenix.View, root: unquote(root)
      import Plug.Conn, only: [get_session: 2]
      import Brando.Images.Helpers

      # Use Phoenix.HTML to import all HTML functions (forms, tags, etc)
      use Phoenix.HTML

      import Phoenix.Controller, only: [get_flash: 2]

      # Functions defined here are available to all other views/templates
      use Brando.HTML

      def csrf_token(conn), do: conn.resp_cookies["_csrf_token"]
    end
  end
end