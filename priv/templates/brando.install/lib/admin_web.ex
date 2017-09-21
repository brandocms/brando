defmodule <%= application_module %>.Admin.Web do
  @moduledoc """
  A module that keeps using definitions for controllers,
  views and so on for use in your apps Admin backend.

  This can be used in your application as:

      use <%= application_module %>.Admin.Web, :controller
      use <%= application_module %>.Admin.Web, :view

  The definitions below will be executed for every view,
  controller, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below.
  """
  def schema do
    quote do
      use Ecto.Schema

      import Ecto
      import Ecto.Changeset
      import Ecto.Query, only: [from: 1, from: 2]
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, namespace: <%= application_module %>.Admin.Web
      alias <%= application_module %>.Repo
      import Ecto
      import Ecto.Query, only: [from: 1, from: 2]
      import <%= application_module %>.Web.Router.Helpers
      import <%= application_module %>.Web.Backend.Gettext
    end
  end

  def view do
    helpers = Brando.helpers()
    quote do
      use Phoenix.View, root: "lib/<%= application_name %>/web/templates",
                        namespace: <%= application_module %>.Web

      # Import convenience functions from controllers
      import Phoenix.Controller, only: [get_csrf_token: 0, get_flash: 2, view_module: 1]
      import Brando.Utils, only: [media_url: 0, media_url: 1,
                                  current_user: 1, app_name: 0, img_url: 3]

      # Alias URL helpers from the router as Helpers
      alias unquote(helpers)

      # Use all HTML functionality (forms, tags, etc)
      use Phoenix.HTML
      use Brando.HTML

      import <%= application_module %>.Web.Router.Helpers
      import <%= application_module %>.Web.ErrorHelpers
      import <%= application_module %>.Web.Backend.Gettext
    end
  end

  def router do
    quote do
      use Phoenix.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
      alias <%= application_module %>.Repo
      import Ecto
      import Ecto.Query, only: [from: 1, from: 2]
      import <%= application_module %>.Web.Backend.Gettext
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
