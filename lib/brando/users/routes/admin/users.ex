defmodule Brando.Users.Admin.Routes do
  @moduledoc """
  Routes for Brando.Users

  ## Usage:

  In `router.ex`

      scope "/admin", as: :admin do
        pipe_through :admin
        user_resources "/brukere", model: Brando.Users.Model.User

  """
  alias Brando.Users.Admin.UserController
  alias Brando.Users.Model.User

  @doc """
  Defines "RESTful" endpoints for the users resource.
  """
  defmacro user_resources(path, ctrl, opts) do
    add_user_resources path, ctrl, opts
  end

  @doc """
  See user_resources/2
  """
  defmacro user_resources(path, opts) do
    add_user_resources path, UserController, opts
  end

  @doc """
  See user_resources/2
  """
  defmacro user_resources(path) do
    add_user_resources path, UserController, []
  end

  defp add_user_resources(path, controller, opts) do
    if model = Keyword.get(opts, :model) do
      options = Keyword.put([], :private, quote(do: %{model: unquote(model)}))
    else
      options = Keyword.put([], :private, quote(do: %{model: User}))
    end
    quote do
      opts = unquote(options)
      ctrl = unquote(controller)
      path = unquote(path)
      get "#{path}", ctrl, :index, opts
      get "#{path}/profil", ctrl, :profile, opts
      get "#{path}/ny", ctrl, :new, opts
      get "#{path}/:id/endre", ctrl, :edit, opts
      get "#{path}/:id", ctrl, :show, opts
      post "#{path}", ctrl, :create, opts
      delete "#{path}/:id", ctrl, :delete, opts
      patch "#{path}/:id", ctrl, :update, opts
      put "#{path}/:id", ctrl, :update, Keyword.put(opts, :as, nil)
    end
  end
end