defmodule BrandoAdmin do
  @moduledoc """
  A module that keeps using definitions for controllers,
  views and so on.

  This can be used in your application as:

      use BrandoAdmin, :controller
      use BrandoAdmin, :view

  Keep the definitions in this module short and clean,
  mostly focused on imports, uses and aliases.
  """

  defp view_helpers do
    quote do
      import Brando.Utils,
        only: [media_url: 0, media_url: 1, current_user: 1, app_name: 0, img_url: 3]

      # Import all HTML functions (forms, tags, etc)
      use Phoenix.HTML
      use Brando.HTML

      # Import LiveView and .heex helpers (live_render, live_patch, <.form>, etc)
      import Phoenix.LiveView.Helpers
      import Plug.Conn, only: [get_session: 2]

      # Import basic rendering functionality (render, render_layout, etc)
      import Phoenix.View
      import BrandoAdmin.ErrorHelpers

      alias Phoenix.LiveView.JS
    end
  end

  def view do
    quote do
      use Phoenix.View, root: "lib/brando_admin/templates"
      import Brando.Gettext
      unquote(view_helpers())
    end
  end

  def controller do
    helpers = Brando.helpers()
    repo = Brando.repo()

    quote do
      use Phoenix.Controller

      import Ecto
      import Ecto.Query, only: [from: 1, from: 2]

      import Brando.Utils, only: [current_user: 1, helpers: 1]
      import Brando.Utils.Schema, only: [put_creator: 2]

      # Alias the data repository as a convenience
      alias unquote(repo)

      # Alias URL helpers from the router
      alias unquote(helpers)
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView,
        layout: {BrandoAdmin.LayoutView, "live.html"}

      unquote(view_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(view_helpers())
    end
  end

  def context do
    quote do
      import Brando.SoftDelete.Query
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
