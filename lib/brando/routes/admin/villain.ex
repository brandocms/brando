defmodule Brando.Villain.Routes.Admin.API do
  @moduledoc """
  Routes for Brando.Villain

  ## Usage:

  In `router.ex`

      scope "/admin", as: :admin do
        pipe_through :admin
        api_villain_routes()
      end

  """

  @doc """
  Defines "RESTful" endpoints for the news resource.
  """
  defmacro api_villain_routes() do
    add_villain_routes("", Brando.VillainController)
  end

  defp add_villain_routes(path, controller) do
    quote do
      path = unquote(path)
      ctrl = unquote(controller)
      opts = []

      post "#{path}/villain/upload/:slug", ctrl, :upload_image, opts
      get "#{path}/villain/browse/:slug", ctrl, :browse_images, opts
      get "#{path}/villain/slideshows/:slug", ctrl, :slideshow, opts
      get "#{path}/villain/slideshows", ctrl, :slideshows, opts
      post "#{path}/villain/imagedata/:id", ctrl, :image_info, opts
      post "#{path}/:x/villain/imagedata/:id", ctrl, :image_info, opts
      post "#{path}/:x/edit/villain/imagedata/:id", ctrl, :image_info, opts
    end
  end
end
