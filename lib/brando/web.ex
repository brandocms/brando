defmodule Brando.Web do
  @moduledoc """
  A module that keeps using definitions for controllers,
  views and so on.

  This can be used in your application as:

      use Brando.Web, :controller
      use Brando.Web, :view

  Keep the definitions in this module short and clean,
  mostly focused on imports, uses and aliases.
  """

  def view do
    helpers = Brando.helpers()
    quote do
      use Phoenix.View, root: "web/templates"

      # Import convenience functions from controllers
      import Phoenix.Controller, only: [get_flash: 2]

      # Alias URL helpers from the router as Helpers
      alias unquote(helpers)

      import Plug.Conn, only: [get_session: 2]
      import Brando.Utils, only: [media_url: 0, media_url: 1,
                                  current_user: 1, app_name: 0, img_url: 3]

      # Import all HTML functions (forms, tags, etc)
      use Phoenix.HTML
      use Brando.HTML
    end
  end

  def controller do
    helpers = Brando.helpers()
    repo = Brando.repo
    quote do
      use Phoenix.Controller
      import Brando.Meta.Controller
      import Brando.Utils, only: [current_user: 1]

      # Alias the data repository as a convenience
      alias unquote(repo)

      # Alias URL helpers from the router
      alias unquote(helpers)
    end
  end

  def model do
    repo = Brando.repo
    quote do
      use Ecto.Model

      # Alias the data repository as a convenience
      alias unquote(repo)
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
