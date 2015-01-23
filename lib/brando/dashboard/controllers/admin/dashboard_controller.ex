defmodule Brando.Dashboard.Admin.DashboardController do
  @moduledoc """
  A module for the admin dashboard.

  ## Example

      use Brando.Dashboard.Admin.DashboardController

  """
  defmacro __using__(_) do
    quote do
      use Phoenix.Controller

      plug :put_layout, @layout
      plug :action

      @doc """
      Renders the main dashboard for the admin area.
      """
      def dashboard(conn, _params) do
        conn
        |> render
      end

      defoverridable [dashboard: 2]
    end
  end
end
