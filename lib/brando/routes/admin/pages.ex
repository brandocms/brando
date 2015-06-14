defmodule Brando.Routes.Admin.Pages do
  @moduledoc """
  Routes for Brando.Pages

  ## Usage:

  In `router.ex`

      scope "/admin", as: :admin do
        pipe_through :admin
        page_routes "/pages", model: Brando.Page

  """
  alias Brando.Admin.PageController
  alias Brando.Admin.PageFragmentController
  alias Brando.Page
  alias Brando.PageFragment

  @doc """
  Defines "RESTful" endpoints for the pages resource.
  """
  defmacro page_routes(path, ctrl, opts) do
    add_page_routes(path, ctrl, opts)
  end

  @doc """
  See page_routes/2
  """
  defmacro page_routes(path, opts) do
    add_page_routes(path, PageController, opts)
  end

  @doc """
  See page_routes/2
  """
  defmacro page_routes(path), do:
    add_page_routes(path, PageController, [])

  defp add_page_routes(path, controller, opts) do
    map = %{}
          |> Map.put(:model, Keyword.get(opts, :model, Page))
          |> Map.put(:fragment_model, Keyword.get(opts, :fragment_model, PageFragment))
    options = Keyword.put([], :private, Macro.escape(map))
    quote do
      path = unquote(path)
      ctrl = unquote(controller)
      opts = unquote(options)
      fctrl = PageFragmentController

      get    "#{path}/fragmenter",                            fctrl, :index,          opts
      get    "#{path}/fragmenter/ny",                         fctrl, :new,            opts
      get    "#{path}/fragmenter/:id",                        fctrl, :show,           opts
      get    "#{path}/fragmenter/:id/endre",                  fctrl, :edit,           opts
      get    "#{path}/fragmenter/:id/slett",                  fctrl, :delete_confirm, opts
      post   "#{path}/fragmenter",                            fctrl, :create,         opts
      delete "#{path}/fragmenter/:id",                        fctrl, :delete,         opts
      patch  "#{path}/fragmenter/:id",                        fctrl, :update,         opts
      put    "#{path}/fragmenter/:id",                        fctrl, :update,         Keyword.put(opts, :as, nil)

      get    "#{path}",                            ctrl, :index,          opts
      post   "#{path}/villain/last-opp/:slug",     ctrl, :upload_image,   opts
      get    "#{path}/villain/bla/:slug",          ctrl, :browse_images,  opts
      post   "#{path}/villain/bildedata/:id",      ctrl, :image_info,     opts
      post   "#{path}/:page_id/villain/bildedata/:id",      ctrl, :image_info,     opts
      get    "#{path}/ny",                         ctrl, :new,            opts
      get    "#{path}/:id",                        ctrl, :show,           opts
      get    "#{path}/:id/endre",                  ctrl, :edit,           opts
      get    "#{path}/:id/slett",                  ctrl, :delete_confirm, opts
      post   "#{path}",                            ctrl, :create,         opts
      delete "#{path}/:id",                        ctrl, :delete,         opts
      patch  "#{path}/:id",                        ctrl, :update,         opts
      put    "#{path}/:id",                        ctrl, :update,         Keyword.put(opts, :as, nil)
    end
  end
end