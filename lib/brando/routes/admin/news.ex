defmodule Brando.Routes.Admin.News do
  @moduledoc """
  Routes for Brando.News

  ## Usage:

  In `router.ex`

      scope "/admin", as: :admin do
        pipe_through :admin
        post_routes "/news", model: Brando.Post

  """
  import Brando.Routes.Admin.Villain

  alias Brando.Admin.PostController
  alias Brando.Post

  @doc """
  Defines "RESTful" endpoints for the news resource.
  """
  defmacro post_routes(path, ctrl, opts) do
    add_post_routes(path, ctrl, opts)
  end

  @doc """
  See post_routes/2
  """
  defmacro post_routes(path, opts) do
    add_post_routes(path, PostController, opts)
  end

  @doc """
  See post_routes/2
  """
  defmacro post_routes(path), do:
    add_post_routes(path, PostController, [])

  defp add_post_routes(path, controller, opts) do
    map = Map.put(%{}, :model, Keyword.get(opts, :model, Post))
    options = Keyword.put([], :private, Macro.escape(map))
    quote do
      path = unquote(path)
      ctrl = unquote(controller)
      opts = unquote(options)

      villain_routes path, ctrl

      get    "#{path}",                                 ctrl, :index,          opts
      get    "#{path}/ny",                              ctrl, :new,            opts
      get    "#{path}/:id",                             ctrl, :show,           opts
      get    "#{path}/:id/endre",                       ctrl, :edit,           opts
      get    "#{path}/:id/slett",                       ctrl, :delete_confirm, opts
      post   "#{path}",                                 ctrl, :create,         opts
      delete "#{path}/:id",                             ctrl, :delete,         opts
      patch  "#{path}/:id",                             ctrl, :update,         opts
      put    "#{path}/:id",                             ctrl, :update,         Keyword.put(opts, :as, nil)
    end
  end
end