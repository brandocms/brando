defmodule Brando.Menu do
  @moduledoc """
  A module for administration area menus.

  ## Example

      use Brando.Menu
      menu %{
        name: "Admin", anchor: "admin", bgcolor: "#ffaaff",
          icon: "fa fa-dashboard icon",
          submenu: [%{name: "Dash", url: admin_dashboard_path(:dashboard)}]}

  """

  defmacro __using__(_) do
    quote do
      Module.register_attribute(__MODULE__, :menus, accumulate: true)
      import unquote(__MODULE__)
      @before_compile Brando.Menu
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    Brando.Menu.compile(Module.get_attribute(env.module, :menus))
  end

  @doc """
  A macro which defines an administration menu point.

  ## Usage

      menu %{
        name: "Admin", anchor: "admin", bgcolor: "#ffaaff",
          icon: "fa fa-dashboard icon",
          submenu: [%{name: "Dash", url: admin_dashboard_path(:dashboard)}]}

  """
  defmacro menu(contents) do
    quote bind_quoted: [contents: Macro.escape(contents)] do
      @menus contents
    end
  end

  defmacro menu(_, _, _) do
    raise "menu/3 is deprecated. Use menu/1 with gettext.\n\n" <>
          Exception.format_stacktrace(System.stacktrace)
  end

  @doc """
  Compile the `menus` down to a module attribute
  """
  def compile(menus) do
    menus =
      for contents <- menus do
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
      def get_menu() do
        unquote(contents)
      end
    end
  end
end
