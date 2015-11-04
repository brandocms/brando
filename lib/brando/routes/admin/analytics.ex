defmodule Brando.Routes.Admin.Analytics do
  @moduledoc """
  Routes for Brando's analytics

  ## Usage:

  In `router.ex`

      scope "/admin", as: :admin do
        pipe_through :admin
        analytics_routes "/"

  """

  defmacro analytics_routes(path, opts \\ []), do:
    add_resources(path, opts)

  defp add_resources(path, opts) do
    quote do
      ctrl = Brando.Admin.AnalyticsController

      path = unquote(path)
      opts = unquote(opts)

      get "#{path}/views",     ctrl, :views,     opts
      get "#{path}/referrals", ctrl, :referrals, opts
    end
  end
end
