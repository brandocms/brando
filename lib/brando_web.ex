defmodule BrandoWeb do
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
    quote do
      use Phoenix.View, root: "lib/brando_web/templates"

      # Import convenience functions from controllers
      import Phoenix.Controller, only: [get_flash: 2]
      import Phoenix.LiveView.Helpers
      import Surface

      import Plug.Conn, only: [get_session: 2]

      import Brando.Utils,
        only: [media_url: 0, media_url: 1, current_user: 1, app_name: 0, img_url: 3]

      # Import all HTML functions (forms, tags, etc)
      use Phoenix.HTML
      use Brando.HTML

      import Brando.Gettext
      import BrandoAdmin.ErrorHelpers
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

  def schema do
    repo = Brando.repo()

    quote do
      use Ecto.Schema

      import Ecto
      import Ecto.Changeset
      import Ecto.Query, only: [from: 1, from: 2]
      import Brando.Utils.Schema

      # Alias the data repository as a convenience
      alias unquote(repo)
    end
  end

  def absinthe do
    quote do
      # Provides us with a DSL for defining GraphQL Types
      use Absinthe.Schema.Notation
      import Absinthe.Resolution.Helpers
    end
  end

  def resolver do
    quote do
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
