defmodule BrandoWeb do
  defmacro __using__(which) when is_atom(which) do
    apply(BrandoWeb, which, [])
  end

  def legacy_controller do
    gettext_module = Brando.web_module(Gettext)
    routes_module = Brando.web_module(Router.Helpers)

    quote do
      use Phoenix.Controller,
        namespace: Brando.config(:web_module),
        layouts: [html: Brando.web_module(Layouts)]

      import unquote(gettext_module)
      import Brando.Plug.HTML
      import Plug.Conn

      alias unquote(routes_module), as: Routes
    end
  end

  def controller do
    gettext_module = Brando.web_module(Gettext)
    routes_module = Brando.web_module(Router.Helpers)

    quote do
      use Phoenix.Controller,
        namespace: Brando.config(:web_module),
        formats: [:html, :json],
        layouts: [html: Brando.web_module(Layouts)]

      import unquote(gettext_module)
      import Brando.Plug.HTML
      import Plug.Conn

      alias unquote(routes_module), as: Routes
    end
  end

  def migration do
    quote do
      import Brando.SoftDelete.Migration
    end
  end

  def context do
    quote do
      import Brando.Query
      import Brando.SoftDelete.Query
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "lib/animaskin_web/templates",
        namespace: AnimaskinWeb

      # Import convenience functions from controllers
      import Phoenix.Controller, only: [get_csrf_token: 0, get_flash: 2, view_module: 1]

      unquote(view_helpers())
    end
  end

  def router do
    quote do
      use Phoenix.Router
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel

      alias Animaskin.Repo
      import Ecto
      import Ecto.Query

      import Brando.web_module(Gettext)
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  def html_helpers do
    error_module = Brando.web_module(ErrorHelpers)
    gettext_module = Brando.web_module(Gettext)
    routes_module = Brando.web_module(Router.Helpers)

    quote do
      import Phoenix.HTML
      import Phoenix.HTML.Form
      import Phoenix.HTML.Tag, only: [csrf_meta_tag: 0]
      alias Phoenix.LiveView.JS

      import Brando.Utils,
        only: [media_url: 0, media_url: 1, current_user: 1, app_name: 0, img_url: 3]

      # Import all HTML functions (forms, tags, etc)
      use Brando.HTML

      # Import LiveView and .heex helpers (live_render, live_patch, <.form>, etc)
      import Phoenix.Component
      import Plug.Conn, only: [get_session: 2]

      import unquote(error_module)
      import unquote(gettext_module)
      alias unquote(routes_module), as: Routes

      # Routes generation with the ~p sigil
      # unquote(verified_routes())
    end
  end

  def view_helpers do
    error_module = Brando.web_module(ErrorHelpers)
    gettext_module = Brando.web_module(Gettext)
    routes_module = Brando.web_module(Router.Helpers)

    quote do
      # Use all HTML functionality (forms, tags, etc)
      use Phoenix.HTML
      import Phoenix.Component

      import Brando.HTML
      import Brando.Utils
      import Brando.Pages, only: [render_fragment: 2, render_fragment: 3, get_var: 2]
      import Brando.I18n.Helpers

      import unquote(error_module)
      import unquote(gettext_module)
      alias unquote(routes_module), as: Routes
    end
  end
end
