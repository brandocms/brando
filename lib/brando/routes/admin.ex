defmodule Brando.Routes.Admin do
  @moduledoc """
  Routes for admin apps

  ## Usage:

  In `router.ex`

      scope "/admin", as: :admin do
        pipe_through :admin
        admin_routes "/brukere", MyApp.MyController

  """
  require Phoenix.Router

  @doc """
  Defines "RESTful" endpoints for the admins resource.
  """
  defmacro admin_routes(path, ctrl), do:
    add_admin_routes(path, ctrl)

  defp add_admin_routes(path, controller) do
    quote do
      ctrl = unquote(controller)
      path = unquote(path)
      get   "#{path}/:id/delete",    ctrl, :delete_confirm
      Phoenix.Router.resources path, ctrl
    end
  end
end