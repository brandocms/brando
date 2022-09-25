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
      import Phoenix.Component
      import Plug.Conn, only: [get_session: 2]

      # Import basic rendering functionality (render, render_layout, etc)
      import Phoenix.View
      import BrandoAdmin.ErrorHelpers

      import BrandoAdmin.Utils,
        only: [
          prepare_subform_component: 1,
          prepare_input_component: 1,
          toggle_dropdown: 1,
          toggle_dropdown: 2,
          show_dropdown: 1,
          show_dropdown: 2,
          hide_dropdown: 1,
          hide_dropdown: 2,
          toggle_drawer: 1,
          toggle_drawer: 2,
          show_modal: 1,
          show_modal: 2,
          hide_modal: 1,
          hide_modal: 2,
          make_id: 1,
          make_uid: 3
        ]

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

      on_mount {BrandoAdmin.Hooks, :urls}

      unquote(view_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(view_helpers())
    end
  end

  def component do
    quote do
      use Phoenix.Component
      import Brando.HTML

      import BrandoAdmin.Utils,
        only: [
          prepare_input_component: 1,
          toggle_dropdown: 1,
          toggle_dropdown: 2,
          show_dropdown: 1,
          show_dropdown: 2,
          hide_dropdown: 1,
          hide_dropdown: 2,
          toggle_drawer: 1,
          toggle_drawer: 2,
          show_modal: 1,
          show_modal: 2,
          hide_modal: 1,
          hide_modal: 2,
          make_id: 1,
          make_uid: 3
        ]
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
