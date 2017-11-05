defmodule Brando.Images.Routes.Admin.API do
  @moduledoc """
  Routes for Brando.Images

  ## Usage:

  In `router.ex`

      scope "/admin", as: :admin do
        pipe_through :admin
        image_routes "/images"

  """

  alias Brando.Admin.ImageController
  alias Brando.Admin.ImageSeriesController
  alias Brando.Admin.ImageCategoryController
  alias Brando.Image
  alias Brando.ImageSeries
  alias Brando.ImageCategory

  defmacro api_image_routes(path, opts \\ []), do:
    add_resources(path, opts)

  defp add_resources(path, opts) do
    priv_map = %{}
    |> Map.put(:image_schema, Keyword.get(opts, :image_schema, Image))
    |> Map.put(:series_schema, Keyword.get(opts, :series_schema, ImageSeries))
    |> Map.put(:category_schema, Keyword.get(opts, :category_schema,ImageCategory))
    options = Keyword.put([], :private, Macro.escape(priv_map))

    # API routes
    quote do
      path = unquote(path)
      opts = unquote(options)

      post "#{path}/upload/image_series/:image_series_id", Brando.Admin.API.Images.UploadController, :post, opts
    end
  end
end
