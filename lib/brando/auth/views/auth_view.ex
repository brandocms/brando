defmodule Brando.Auth.AuthView do
  # The quoted expression returned by this block is applied
  # to this module and all other views that use this module.
  defmacro __using__(options) do
    require Logger
    root = Dict.fetch! options, :root
    quote do
      use Phoenix.View, root: unquote(root)
      import Plug.Conn, only: [get_session: 2]
      # Import common functionality
      import unquote(Brando.get_helpers) #MyApp.Router.Helpers

      # Use Phoenix.HTML to import all HTML functions (forms, tags, etc)
      use Phoenix.HTML

      # Functions defined here are available to all other views/templates
      def path(conn) do
        Path.join(["/"] ++ conn.path_info)
      end

      def is_active?(url_to_match, current_path) do
        case url_to_match == current_path do
          true  -> "active"
          false -> ""
        end
      end

      def format_date(%Ecto.DateTime{year: year, month: month, day: day}) do
        "#{day}/#{month}/#{year}"
      end

      def format_date(_erroneus_date) do
        ">>DATE ERROR<<"
      end

      def zero_pad(int) do
        String.rjust(Integer.to_string(int), 3, ?0)
      end

      def first_name(full_name) do
        full_name
        |> String.split
        |> hd
      end

      def current_user(conn) do
        get_session(conn, :current_user)
      end
    end
  end
end