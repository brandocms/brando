defmodule Brando.Routes.Admin.Villain do
  @moduledoc """
  Routes for Brando.Villain

  ## Usage:

  In `router.ex`

      scope "/admin", as: :admin do
        pipe_through :admin
        scope "/mymodule" do
          villain_routes MyController
        end
      end

  """

  @doc """
  Defines "RESTful" endpoints for the news resource.
  """
  defmacro villain_routes(ctrl) do
    add_villain_routes("", ctrl)
  end

  @doc """
  See villain_routes/2
  """
  defmacro villain_routes(path, ctrl) do
    add_villain_routes(path, ctrl)
  end

  defp add_villain_routes(path, controller) do
    quote do
      path = unquote(path)
      ctrl = unquote(controller)
      opts = []

      post "#{path}/villain/upload/:slug",           ctrl, :upload_image,  opts
      get  "#{path}/villain/browse/:slug",           ctrl, :browse_images, opts
      get  "#{path}/villain/imageseries",            ctrl, :imageseries,   opts
      post "#{path}/villain/imagedata/:id",          ctrl, :image_info,    opts
      post "#{path}/:x/villain/imagedata/:id",      ctrl, :image_info,    opts
      post "#{path}/:x/edit/villain/imagedata/:id", ctrl, :image_info,    opts
    end
  end
end
