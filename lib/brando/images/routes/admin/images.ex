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
    options = Keyword.put(options, :private, quote(do: %{image_model: unquote(Keyword.get(opts, :image_model) || Image)}))
    options = Keyword.put(options, :private, quote(do: %{series_model: unquote(Keyword.get(opts, :series_model) || ImageSeries)}))
    options = Keyword.put(options, :private, quote(do: %{category_model: unquote(Keyword.get(opts, :category_model) || ImageCategory)}))

    quote do
      image_ctrl = ImageController
      series_ctrl = ImageSeriesController
      categories_ctrl = ImageCategoryController

      path = unquote(path)
      opts = unquote(options)

      get "#{path}", image_ctrl, :index, opts
      get "#{path}/serier", series_ctrl, :index, Keyword.put(opts, :as, "image_series")
      get "#{path}/serier/ny", series_ctrl, :new, Keyword.put(opts, :as, "image_series")
      post "#{path}/serier", series_ctrl, :create, Keyword.put(opts, :as, "image_series")
      get "#{path}/kategorier", categories_ctrl, :index, Keyword.put(opts, :as, "image_category")
      get "#{path}/kategorier/slett/:id", categories_ctrl, :delete_confirm, Keyword.put(opts, :as, "image_category")
      delete "#{path}/kategorier", categories_ctrl, :delete, Keyword.put(opts, :as, "image_category")
      get "#{path}/kategorier/ny", categories_ctrl, :new, Keyword.put(opts, :as, "image_category")
      post "#{path}/kategorier", categories_ctrl, :create, Keyword.put(opts, :as, "image_category")
    end
  end
end