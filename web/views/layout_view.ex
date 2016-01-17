defmodule Brando.Admin.LayoutView do
  @moduledoc """
  Main layout view for Brando admin.
  """
  use Brando.Web, :view

  @doc """
  Returns menus for admin.
  Modules are registered with `:modules` in `config.exs`

  ## Example:

      config :brando, Brando.Menu,
        modules: [Brando.Admin, Brando.Users]

  """
  def get_menus() do
    modules = Brando.config(Brando.Menu)[:modules]
    colors = Brando.config(Brando.Menu)[:colors]

    for {mod, color} <- Enum.zip(modules, colors) do
      {color, mod.get_menu()}
    end
  end
end
