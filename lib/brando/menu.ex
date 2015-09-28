defmodule Brando.Menu do
  @moduledoc """
  A module for administration area menus.

  ## Example

      use Brando.Menu
      menu "Admin",
        %{name: "Admin", anchor: "admin", bgcolor: "#ffaaff",
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

      menu "Admin",
        %{name: "Admin", anchor: "admin", bgcolor: "#ffaaff",
          icon: "fa fa-dashboard icon",
          submenu: [%{name: "Dash", url: admin_dashboard_path(:dashboard)}]}

  """
  defmacro menu(_, _) do
    raise "menu/2 is deprecated. Use menu/3 with added :language as first " <>
          "parameter\n\n#{Exception.format_stacktrace(System.stacktrace)}"
  end

  defmacro menu(language, name, contents) do
    quote bind_quoted: [language: language, name: name,
                        contents: Macro.escape(contents)] do
      @menus {language, name, contents}
    end
  end

  @doc """
  Compile the `menus` down to a module attribute
  """
  def compile(menus) do
    menus =
      for {language, name, contents} <- menus do
        defmenu(language, name, contents)
      end

    quote do
      unquote(menus)
    end
  end

  defp defmenu(language, name, contents) do
    quote do
      @doc """
      Get the menu for the module `menu/2` was called from.
      """
      def get_menu(unquote(language)) do
        {unquote(name), unquote(contents)}
      end
    end
  end
end
