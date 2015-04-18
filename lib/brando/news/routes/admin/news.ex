defmodule Brando.News.Admin.Routes do
  @moduledoc """
  Routes for Brando.News

  ## Usage:

  In `router.ex`

      scope "/admin", as: :admin do
        pipe_through :admin
        post_resources "/news", model: Brando.Post

  """
  alias Brando.News.Admin.PostController
  alias Brando.Post

  @doc """
  Defines "RESTful" endpoints for the news resource.
  """
  defmacro post_resources(path, ctrl, opts) do
    add_post_resources path, ctrl, opts
  end

  @doc """
  See post_resources/2
  """
  defmacro post_resources(path, opts) do
    add_post_resources path, PostController, opts
  end

  @doc """
  See post_resources/2
  """
  defmacro post_resources(path) do
    add_post_resources path, PostController, []
  end

  defp add_post_resources(path, controller, opts) do
    map = Map.put(%{}, :model, Keyword.get(opts, :model) || Post)
    options = Keyword.put([], :private, Macro.escape(map))
    quote do
      path = unquote(path)
      ctrl = unquote(controller)
      opts = unquote(options)

      get "#{path}", ctrl, :index, opts
      post "#{path}/villain/last-opp/:id", ctrl, :upload_image, opts
      get "#{path}/villain/bla/:id", ctrl, :browse_images, opts
      post "#{path}/villain/bildedata/:id", ctrl, :image_info, opts
      get "#{path}/ny", ctrl, :new, opts
      get "#{path}/:id", ctrl, :show, opts
      get "#{path}/:id/endre", ctrl, :edit, opts
      get "#{path}/:id/slett", ctrl, :delete_confirm, opts
      post "#{path}", ctrl, :create, opts
      delete "#{path}/:id", ctrl, :delete, opts
      patch "#{path}/:id", ctrl, :update, opts
      put "#{path}/:id", ctrl, :update, Keyword.put(opts, :as, nil)
    end
  end
end