defmodule Brando.Images.Admin.Routes do
  @moduledoc """
  Routes for Brando.Images

  ## Usage:

  In `router.ex`

      scope "/admin", as: :admin do
        pipe_through :admin
        image_resources "/images"

  """
  alias Brando.Images.Admin.ImageController
  alias Brando.Images.Admin.ImageSeriesController
  alias Brando.Images.Admin.ImageCategoryController
  alias Brando.Images.Model.Image
  alias Brando.Images.Model.ImageSeries
  alias Brando.Images.Model.ImageCategory

  defmacro image_resources(path, opts \\ []) do
    add_resources(path, opts)
  end

  defp add_resources(path, opts) do
    options = []
    priv_map = Map.put(%{}, :image_model, Keyword.get(opts, :image_model) || Image)
    priv_map = Map.put(priv_map, :series_model, Keyword.get(opts, :seriesmodel) || ImageSeries)
    priv_map = Map.put(priv_map, :category_model, Keyword.get(opts, :category_model) || ImageCategory)
    options = Keyword.put(options, :private, Macro.escape(priv_map))

    quote do
      image_ctrl = ImageController
      series_ctrl = ImageSeriesController
      categories_ctrl = ImageCategoryController

      path = unquote(path)
      opts = unquote(options)

      get "#{path}", image_ctrl, :index, opts
      get "#{path}/serier", series_ctrl, :index, Keyword.put(opts, :as, "image_series")
      get "#{path}/serier/ny", series_ctrl, :new, Keyword.put(opts, :as, "image_series")
      get "#{path}/serier/:id/endre", series_ctrl, :edit, Keyword.put(opts, :as, "image_series")
      get "#{path}/serier/:id/slett", series_ctrl, :delete_confirm, Keyword.put(opts, :as, "image_series")
      get "#{path}/serier/:id/last-opp", series_ctrl, :upload, Keyword.put(opts, :as, "image_series")
      post "#{path}/serier/:id/last-opp", series_ctrl, :upload_post, Keyword.put(opts, :as, "image_series")
      get "#{path}/serier/:id/sorter", series_ctrl, :sort, Keyword.put(opts, :as, "image_series")
      post "#{path}/serier/:id/sorter", series_ctrl, :sort_post, Keyword.put(opts, :as, "image_series")
      patch "#{path}/serier/:id", series_ctrl, :update, Keyword.put(opts, :as, "image_series")
      put "#{path}/serier/:id", series_ctrl, :update, Keyword.put(opts, :as, nil)
      delete "#{path}/serier/:id", series_ctrl, :delete, Keyword.put(opts, :as, "image_series")
      post "#{path}/serier", series_ctrl, :create, Keyword.put(opts, :as, "image_series")

      get "#{path}/kategorier", categories_ctrl, :index, Keyword.put(opts, :as, "image_category")
      get "#{path}/kategorier/ny", categories_ctrl, :new, Keyword.put(opts, :as, "image_category")
      get "#{path}/kategorier/:id/slett", categories_ctrl, :delete_confirm, Keyword.put(opts, :as, "image_category")
      delete "#{path}/kategorier/:id", categories_ctrl, :delete, Keyword.put(opts, :as, "image_category")
      post "#{path}/kategorier", categories_ctrl, :create, Keyword.put(opts, :as, "image_category")
    end
  end
end