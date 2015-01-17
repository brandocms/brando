defmodule Brando.Dashboard.Admin.DashboardController do
  @doc false
  defmacro __using__(options) do
    layout = Dict.fetch! options, :layout
    #model = Dict.fetch! options, :model

    quote do
      use Phoenix.Controller

      plug :action

      def dashboard(conn, _params) do
        conn
        |> put_layout(unquote(layout))
        |> render
      end

      defoverridable [dashboard: 2]
    end
  end
end
