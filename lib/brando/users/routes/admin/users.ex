defmodule Brando.Users.Admin.Routes do
  @moduledoc """
  Routes for Brando.Users

  ## Usage:

  In `router.ex`

      scope "/admin", as: :admin do
        pipe_through :admin
        user_resources "/brukere", private: %{model: Brando.Users.Model.User}

  """
  alias Phoenix.Router.Resource
  alias Brando.Users.Admin.UserController
  alias Brando.Users.Model.User

  @doc """
  Defines "RESTful" endpoints for the users resource.
  """
  defmacro user_resources(path, ctrl, opts) do
    add_user_resources path, ctrl, opts, do: nil
  end

  @doc """
  See user_resources/2
  """
  defmacro user_resources(path, opts) do
    add_user_resources path, UserController, opts, do: nil
  end

  @doc """
  See user_resources/2
  """
  defmacro user_resources(path) do
    add_user_resources path, UserController, [], do: nil
  end

  defp add_user_resources(path, controller, opts, do: context) do
    if model = Keyword.get(opts, :model) do
      options = Keyword.put([], :private, quote(do: %{model: unquote(model)}))
    else
      options = Keyword.put([], :private, quote(do: %{model: User}))
    end
    quote do
      resource = Resource.build(unquote(path), unquote(controller), unquote(options))
      parm = resource.param
      path = resource.path
      ctrl = resource.controller
      opts = resource.route

      Enum.each [:profile] ++ resource.actions, fn action ->
        case action do
          :index   -> get    "#{path}",                ctrl, :index, opts
          :profile -> get    "#{path}/profil",         ctrl, :profile, opts
          :show    -> get    "#{path}/:#{parm}",       ctrl, :show, opts
          :new     -> get    "#{path}/ny",             ctrl, :new, opts
          :edit    -> get    "#{path}/:#{parm}/endre", ctrl, :edit, opts
          :create  -> post   "#{path}",                ctrl, :create, opts
          :delete  -> delete "#{path}/:#{parm}",       ctrl, :delete, opts
          :update  ->
            patch "#{path}/:#{parm}", ctrl, :update, opts
            put   "#{path}/:#{parm}", ctrl, :update, Keyword.put(opts, :as, nil)
        end
      end
      scope resource.member do
        unquote(context)
      end
    end
  end
end