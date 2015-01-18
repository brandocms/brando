defmodule Brando.Menu do
  defmacro __using__(_) do
    quote do
      Module.register_attribute(__MODULE__, :menus, accumulate: true)
      import unquote(__MODULE__)
      @before_compile Brando.Menu
    end
  end
  @moduledoc """
  A module for administration area menus.
  """

  @doc false
  defmacro __before_compile__(env) do
    Brando.Menu.compile(Module.get_attribute(env.module, :menus))
  end

  @doc """
  A macro which defines an administration menu point.

  ## Usage

      use Brando.Menu
      menu "Admin",
        %{name: "Admin", anchor: "admin", bgcolor: "#ffaaff", icon: "fa fa-dashboard icon",
          submenu: [%{name: "Dashboard", url: admin_dashboard_path(:dashboard)}]}

  """
  defmacro menu(name, contents) do
    quote bind_quoted: [name: name, contents: Macro.escape(contents)] do
      @menus {name, contents}
    end
  end

  def compile(menus) do
    menus =
      for {_name, contents} <- menus do
        defmenu(contents)
      end

    quote do
      unquote(menus)
    end
  end

  defp defmenu(contents) do
    quote do
      @doc """
      Get the menu for the module `menu/2` was called from.
      """
      def get_menu do
        unquote(contents)
      end
    end
  end
end