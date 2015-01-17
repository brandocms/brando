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
      def app_name do
        Brando.config(:app_name)
      end

      def path(conn) do
        Path.join(["/"] ++ conn.path_info)
      end

      def is_active?(url_to_match, current_path) when url_to_match == current_path, do: "active"
      def is_active?(url_to_match, current_path), do: ""

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

      @doc """
      Return the current user set in session.
      """
      def current_user(conn) do
        get_session(conn, :current_user)
      end

      @doc """
      Return joined path of `file` and the :media_url config option
      as set in your app's config.exs.
      """
      def media_path(file) do
        Path.join([Brando.config(:media_url), file])
      end
    end
  end
end