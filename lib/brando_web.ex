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

      use Gettext, backend: unquote(gettext_module)
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
        layouts: [html: Brando.web_module(Layouts), json: Brando.web_module(Layouts)]

      use Gettext, backend: unquote(gettext_module)
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

  @deprecated "use :html"
  def view do
    quote do
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
    gettext_module = Brando.web_module(Gettext)

    quote do
      use Phoenix.Channel

      import Ecto
      import Ecto.Query

      use Gettext, backend: unquote(gettext_module)
    end
  end

  def html do
    quote do
      use Phoenix.Component
      import Phoenix.Controller, only: [get_csrf_token: 0]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  def html_helpers do
    gettext_module = Brando.web_module(Gettext)
    routes_module = Brando.web_module(Router.Helpers)

    quote do
      use Gettext, backend: unquote(gettext_module)
      import Phoenix.HTML
      import Phoenix.HTML.Form
      alias Phoenix.LiveView.JS

      import Brando.Utils,
        only: [media_url: 0, media_url: 1, current_user: 1, app_name: 0, img_url: 3]

      # Import all HTML functions (forms, tags, etc)
      import Brando.HTML
      import Brando.I18n.Helpers
      import Brando.Pages, only: [render_fragment: 2, render_fragment: 3, get_var: 2]

      # Import LiveView and .heex helpers (live_render, live_patch, <.form>, etc)
      import Phoenix.Component
      import Plug.Conn, only: [get_session: 2]

      alias unquote(routes_module), as: Routes

      # Routes generation with the ~p sigil
      # unquote(verified_routes())
    end
  end

  def view_helpers do
    gettext_module = Brando.web_module(Gettext)
    routes_module = Brando.web_module(Router.Helpers)

    quote do
      use Gettext, backend: unquote(gettext_module)
      # Use all HTML functionality (forms, tags, etc)
      import Phoenix.HTML
      import Phoenix.HTML.Form
      # use PhoenixHTMLHelpers
      import Phoenix.Component

      import Brando.HTML
      import Brando.Utils
      import Brando.Pages, only: [render_fragment: 2, render_fragment: 3, get_var: 2]
      import Brando.I18n.Helpers

      alias unquote(routes_module), as: Routes
    end
  end
end
