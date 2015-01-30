defmodule Brando.Admin.LayoutView do
  @moduledoc """
  Main layout view for Brando admin.
  """
  use Brando.AdminView, root: Brando.config(:templates_path)

  @doc """
  Returns menus for admin.
  Modules are registered with `:user_modules` in `config.exs`

  ## Example:

      config :brando,
        use_modules: [Brando.Admin, Brando.Users]

  """
  def get_menus do
    modules = Brando.config(:use_modules)
    colors = Brando.config(:menu_colors)
    for {mod, color} <- Enum.zip(modules, colors) do
      {color, Module.concat(mod, "Menu").get_menu}
    end
  end
end