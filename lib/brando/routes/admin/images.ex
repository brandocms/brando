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
    |> Map.put(:category_model, Keyword.get(opts, :category_model, ImageCategory))
    options = Keyword.put([], :private, Macro.escape(priv_map))

    quote do
      image_ctrl = ImageController
      series_ctrl = ImageSeriesController
      categories_ctrl = ImageCategoryController
      is_opts = Keyword.put(opts, :as, "image_series")

      path = unquote(path)
      opts = unquote(options)

      get    "#{path}",                           image_ctrl,      :index,           opts
      post   "#{path}/slett-valgte-bilder",       image_ctrl,      :delete_selected, opts
      get    "#{path}/serier",                    series_ctrl,     :index,           is_opts
      get    "#{path}/serier/ny/:id",             series_ctrl,     :new,             is_opts
      get    "#{path}/serier/:id/endre",          series_ctrl,     :edit,            is_opts
      get    "#{path}/serier/:id/slett",          series_ctrl,     :delete_confirm,  is_opts
      get    "#{path}/serier/:id/last-opp",       series_ctrl,     :upload,          is_opts
      post   "#{path}/serier/:id/last-opp",       series_ctrl,     :upload_post,     is_opts
      get    "#{path}/serier/:filter/sorter",     series_ctrl,     :sequence,        is_opts
      post   "#{path}/serier/:filter/sorter",     series_ctrl,     :sequence_post,   is_opts
      patch  "#{path}/serier/:id",                series_ctrl,     :update,          is_opts
      put    "#{path}/serier/:id",                series_ctrl,     :update,          Keyword.put(opts, :as, nil)
      delete "#{path}/serier/:id",                series_ctrl,     :delete,          is_opts
      post   "#{path}/serier",                    series_ctrl,     :create,          is_opts

      get    "#{path}/kategorier",                categories_ctrl, :index,           Keyword.put(opts, :as, "image_category")
      get    "#{path}/kategorier/ny",             categories_ctrl, :new,             Keyword.put(opts, :as, "image_category")
      get    "#{path}/kategorier/:id/endre",      categories_ctrl, :edit,            Keyword.put(opts, :as, "image_category")
      get    "#{path}/kategorier/:id/konfigurer", categories_ctrl, :configure,       Keyword.put(opts, :as, "image_category")
      patch  "#{path}/kategorier/:id/konfigurer", categories_ctrl, :configure_patch, Keyword.put(opts, :as, "image_category")
      get    "#{path}/kategorier/:id/slett",      categories_ctrl, :delete_confirm,  Keyword.put(opts, :as, "image_category")
      patch  "#{path}/kategorier/:id",            categories_ctrl, :update,          Keyword.put(opts, :as, "image_category")
      delete "#{path}/kategorier/:id",            categories_ctrl, :delete,          Keyword.put(opts, :as, "image_category")
      post   "#{path}/kategorier",                categories_ctrl, :create,          Keyword.put(opts, :as, "image_category")
    end
  end
end