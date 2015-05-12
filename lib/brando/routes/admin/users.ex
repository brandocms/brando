defmodule Brando.Routes.Admin.Users do
  @moduledoc """
  Routes for Brando.Users

  ## Usage:

  In `router.ex`

      scope "/admin", as: :admin do
        pipe_through :admin
        user_routes "/brukere", model: Brando.User

  """
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

      get    "#{path}",              ctrl, :index,          opts
      get    "#{path}/profil",       ctrl, :profile,        opts
      get    "#{path}/profil/endre", ctrl, :profile_edit,   opts
      patch  "#{path}/profil/endre", ctrl, :profile_update, opts
      get    "#{path}/ny",           ctrl, :new,            opts
      get    "#{path}/:id/endre",    ctrl, :edit,           opts
      get    "#{path}/:id/slett",    ctrl, :delete_confirm, opts
      get    "#{path}/:id",          ctrl, :show,           opts
      post   "#{path}",              ctrl, :create,         opts
      delete "#{path}/:id",          ctrl, :delete,         opts
      patch  "#{path}/:id",          ctrl, :update,         opts
      put    "#{path}/:id",          ctrl, :update,         Keyword.put(opts, :as, nil)
    end
  end
end