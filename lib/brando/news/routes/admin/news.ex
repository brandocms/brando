defmodule Brando.News.Admin.Routes do
  @moduledoc """
  Routes for Brando.News

  ## Usage:

  In `router.ex`

      scope "/admin", as: :admin do
        pipe_through :admin
        news_resources "/news", private: %{model: Brando.News.Model.Post}

  """
  alias Phoenix.Router.Resource
  alias Brando.News.Admin.PostController
  alias Brando.News.Model.Post

  @doc """
  Defines "RESTful" endpoints for the news resource.
  """
  defmacro news_resources(path, ctrl, opts) do
    add_news_resources path, ctrl, opts, do: nil
  end

  @doc """
  See news_resources/2
  """
  defmacro news_resources(path, opts) do
    add_news_resources path, PostController, opts, do: nil
  end

  @doc """
  See news_resources/2
  """
  defmacro news_resources(path) do
    add_news_resources path, PostController, [], do: nil
  end

  defp add_news_resources(path, controller, options, do: context) do
    if options == [], do: options = quote(do: [private: %{model: Post}])
    quote do
      resource = Resource.build(unquote(path), unquote(controller), unquote(options))
      parm = resource.param
      path = resource.path
      ctrl = resource.controller
      opts = resource.route
      actions = [:index, :edit, :new, :upload_image,
                 :browse_images, :image_info, :show, :create, :update, :delete]

      Enum.each actions, fn action ->
        case action do
          :index         -> get    "#{path}",                    ctrl, :index, opts
          :upload_image  -> post   "#{path}/villain/last-opp/",  ctrl, :upload_image, opts
          :browse_images -> get    "#{path}/villain/bla/",       ctrl, :browse_images, opts
          :image_info    -> post   "#{path}/villain/bildedata/:#{parm}", ctrl, :image_info, opts
          :show          -> get    "#{path}/:#{parm}",           ctrl, :show, opts
          :new           -> get    "#{path}/ny",                 ctrl, :new, opts
          :edit          -> get    "#{path}/:#{parm}/endre",     ctrl, :edit, opts
          :create        -> post   "#{path}",                    ctrl, :create, opts
          :delete        -> delete "#{path}/:#{parm}",           ctrl, :delete, opts
          :update        ->
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