defmodule Brando.Routes.Admin.Images do
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

  defmacro image_routes(path, opts \\ []), do:
    add_resources(path, opts)

  defp add_resources(path, opts) do
    priv_map = %{}
    |> Map.put(:image_model, Keyword.get(opts, :image_model, Image))
    |> Map.put(:series_model, Keyword.get(opts, :series_model, ImageSeries))
    |> Map.put(:category_model, Keyword.get(opts, :category_model,
                                            ImageCategory))
    options = Keyword.put([], :private, Macro.escape(priv_map))

    quote do
      image_ctrl = ImageController
      series_ctrl = ImageSeriesController
      categories_ctrl = ImageCategoryController

      path = unquote(path)
      opts = unquote(options)
      series_opts = Keyword.put(opts, :as, "image_series")
      categories_opts = Keyword.put(opts, :as, "image_category")

      get    "#{path}",                        image_ctrl,
             :index,                           opts
      post   "#{path}/delete-selected-images", image_ctrl,
             :delete_selected,                 opts
      get    "#{path}/series",                 series_ctrl,
             :index,                           series_opts
      get    "#{path}/series/new/:id",         series_ctrl,
             :new,                             series_opts
      get    "#{path}/series/:id/edit",        series_ctrl,
             :edit,                            series_opts
      get    "#{path}/series/:id/delete",      series_ctrl,
             :delete_confirm,                  series_opts
      get    "#{path}/series/:id/upload",      series_ctrl,
             :upload,                          series_opts
      post   "#{path}/series/:id/upload",      series_ctrl,
             :upload_post,                     series_opts
      get    "#{path}/series/:filter/sort",    series_ctrl,
             :sequence,                        series_opts
      post   "#{path}/series/:filter/sort",    series_ctrl,
             :sequence_post,                   series_opts
      patch  "#{path}/series/:id",             series_ctrl,
             :update,                          series_opts
      put    "#{path}/series/:id",             series_ctrl,
             :update,                          Keyword.put(opts, :as, nil)
      delete "#{path}/series/:id",             series_ctrl,
             :delete,                          series_opts
      post   "#{path}/series",                 series_ctrl,
             :create,                          series_opts

      get    "#{path}/categories",               categories_ctrl,
             :index,                             categories_opts
      get    "#{path}/categories/new",           categories_ctrl,
             :new,                               categories_opts
      get    "#{path}/categories/:filter/sort",  categories_ctrl,
             :sequence,                          categories_opts
      post   "#{path}/categories/:filter/sort",  categories_ctrl,
             :sequence_post,                     categories_opts
      get    "#{path}/categories/:id/edit",      categories_ctrl,
             :edit,                              categories_opts
      get    "#{path}/categories/:id/configure", categories_ctrl,
             :configure,                         categories_opts
      patch  "#{path}/categories/:id/configure", categories_ctrl,
             :configure_patch,                   categories_opts
      get    "#{path}/categories/:id/delete",    categories_ctrl,
             :delete_confirm,                    categories_opts
      patch  "#{path}/categories/:id",           categories_ctrl,
             :update,                            categories_opts
      delete "#{path}/categories/:id",           categories_ctrl,
             :delete,                            categories_opts
      post   "#{path}/categories",               categories_ctrl,
             :create,                            categories_opts
    end
  end
end
