defmodule Brando.Dashboard.Routes.Admin do
  @moduledoc """
  Routes for Brando's dashboard

  ## Usage:

  In `router.ex`

      scope "/admin", as: :admin do
        pipe_through :admin
        dashboard_routes "/"

  """

  defmacro dashboard_routes(path, opts \\ []), do:
    add_resources(path, opts)

  defp add_resources(path, opts) do
    quote do
      ctrl = Brando.Admin.DashboardController

      path = unquote(path)
      opts = unquote(opts)

      get "#{path}",                 ctrl, :dashboard,       opts
      get "#{path}/systeminfo",      ctrl, :system_info,     opts
    end
  end
end
