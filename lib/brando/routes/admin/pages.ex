defmodule Brando.Routes.Admin.Pages do
  @moduledoc """
  Routes for Brando.Pages

  ## Usage:

  In `router.ex`

      scope "/admin", as: :admin do
        pipe_through :admin
        page_routes "/pages", model: Brando.Page

  """
  import Brando.Routes.Admin.Villain

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
    map =
      %{}
      |> Map.put(:model, Keyword.get(opts, :model, Page))
      |> Map.put(:fragment_model, Keyword.get(opts, :fragment_model,
                                              PageFragment))
    options = Keyword.put([], :private, Macro.escape(map))
    quote do
      path = unquote(path)
      ctrl = unquote(controller)
      opts = unquote(options)
      nil_opts = Keyword.put(opts, :as, nil)
      fctrl = PageFragmentController

      get    "#{path}/fragments",            fctrl, :index,          opts
      get    "#{path}/fragments/new",        fctrl, :new,            opts
      get    "#{path}/fragments/:id",        fctrl, :show,           opts
      get    "#{path}/fragments/:id/edit",   fctrl, :edit,           opts
      get    "#{path}/fragments/:id/delete", fctrl, :delete_confirm, opts
      post   "#{path}/fragments",            fctrl, :create,         opts
      delete "#{path}/fragments/:id",        fctrl, :delete,         opts
      patch  "#{path}/fragments/:id",        fctrl, :update,         opts
      put    "#{path}/fragments/:id",        fctrl, :update,         nil_opts

      villain_routes path, ctrl

      get    "#{path}",               ctrl, :index,          opts
      get    "#{path}/new",           ctrl, :new,            opts
      get    "#{path}/rerender",      ctrl, :rerender,       opts
      get    "#{path}/:id",           ctrl, :show,           opts
      get    "#{path}/:id/duplicate", ctrl, :duplicate,      opts
      get    "#{path}/:id/edit",      ctrl, :edit,           opts
      get    "#{path}/:id/delete",    ctrl, :delete_confirm, opts
      post   "#{path}",               ctrl, :create,         opts
      delete "#{path}/:id",           ctrl, :delete,         opts
      patch  "#{path}/:id",           ctrl, :update,         opts
      put    "#{path}/:id",           ctrl, :update,         nil_opts
    end
  end
end
