defmodule Brando.Dashboard.Admin.DashboardController do
  @moduledoc """
  A module for the admin dashboard.

  ## Example

      use Brando.Dashboard.Admin.DashboardController

  """
  defmacro __using__(options) do
    layout = Dict.fetch! options, :layout

    quote do
      use Phoenix.Controller

      plug :action

      @doc """
      Renders the main dashboard for the admin area.
      """
      def dashboard(conn, _params) do
        conn
        |> put_layout(unquote(layout))
        |> render
      end

      defoverridable [dashboard: 2]
    end
  end
end
