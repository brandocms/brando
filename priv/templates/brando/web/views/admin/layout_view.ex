defmodule <%= application_name %>.Admin.LayoutView do
  use Brando.AdminView, root: Brando.config(:templates_path)

  def get_menus do
    modules = Brando.config(:use_modules)
    colors = Brando.config(:menu_colors)
    for {mod, color} <- Enum.zip(modules, colors) do
      {color, Module.concat(mod, "Menu").get_menu}
    end
  end
end