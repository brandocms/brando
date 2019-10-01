defmodule <%= application_module %>Web do
  @moduledoc """
  A module that keeps using definitions for controllers,
  views and so on.

  This can be used in your application as:

      use <%= application_module %>Web, :controller
      use <%= application_module %>Web, :view

  The definitions below will be executed for every view,
  controller, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below.
  """

  def schema do
    quote do
      use Brando.JSONLD.Schema
      use Ecto.Schema

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Brando.Utils.Schema
    end
  end

  def controller do
    quote do
      use Phoenix.Controller,
        namespace: <%= application_module %>Web

      import <%= application_module %>Web.Gettext
      import Brando.Plug.HTML
      import Plug.Conn

      alias <%= application_module %>Web.Router.Helpers, as: Routes
    end
  end

  def migration do
    quote do
      import Brando.SoftDelete.Migration
    end
  end

  def context do
    quote do
      import Brando.SoftDelete.Query
    end
  end

  def absinthe do
    quote do
      # Provides us with a DSL for defining GraphQL Types
      use Absinthe.Schema.Notation

      # Enable helpers for batching associated requests
      use Absinthe.Ecto, repo: <%= application_module %>.Repo

      import Absinthe.Ecto
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "lib/<%= application_name %>_web/templates",
        namespace: <%= application_module %>Web

      # Import convenience functions from controllers
      import Phoenix.Controller, only: [get_csrf_token: 0, get_flash: 2, view_module: 1]

      # Use all HTML functionality (forms, tags, etc)
      use Phoenix.HTML

      import Brando.HTML
      import Brando.Utils
      import Brando.Pages, only: [render_fragment: 2, render_fragment: 3]

      import <%= application_module %>Web.ErrorHelpers
      import <%= application_module %>Web.Gettext

      alias <%= application_module %>Web.Router.Helpers, as: Routes
    end
  end

  def router do
    quote do
      use Phoenix.Router
      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def channel do
    quote do
      use Phoenix.Channel

      alias <%= application_module %>.Repo
      import Ecto
      import Ecto.Query

      import <%= application_module %>Web.Gettext
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
