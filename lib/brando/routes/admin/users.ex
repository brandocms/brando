defmodule Brando.Users.Routes.Admin do
  @moduledoc """
  Routes for Brando.Users

  ## Usage:

  In `router.ex`

      scope "/admin", as: :admin do
        pipe_through :admin
        user_routes "/brukere", model: Brando.User

  """
  require Phoenix.Router
  alias Brando.Admin.UserController
  alias Brando.User

  @doc """
  Defines "RESTful" endpoints for the users resource.
  """
  defmacro user_routes(path, ctrl, opts), do:
    add_user_routes(path, ctrl, opts)

  @doc """
  See user_routes/2
  """
  defmacro user_routes(path, opts), do:
    add_user_routes(path, UserController, opts)

  @doc """
  See user_routes/2
  """
  defmacro user_routes(path), do:
    add_user_routes(path, UserController, [])

  defp add_user_routes(path, controller, opts) do
    map = Map.put(%{}, :model, Keyword.get(opts, :model, User))
    options = Keyword.put([], :private, Macro.escape(map))
    quote do
      opts = unquote(options)
      ctrl = unquote(controller)
      path = unquote(path)
      get   "#{path}/profile",      ctrl, :profile, opts
      get   "#{path}/profile/edit", ctrl, :profile_edit, opts
      patch "#{path}/profile/edit", ctrl, :profile_update, opts
      get   "#{path}/:id/delete",   ctrl, :delete_confirm, opts
      Phoenix.Router.resources path, ctrl, opts
    end
  end
end
