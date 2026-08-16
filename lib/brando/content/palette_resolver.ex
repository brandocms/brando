defmodule Brando.Content.PaletteResolver do
  @moduledoc "Tenant-first resolver for shared and site-specific palettes."

  alias Brando.Content.SharedLibrary

  def get_palette(id, site, prefix), do: SharedLibrary.get(:palette, id, site, prefix)
  def get_palette(id, origin, site, prefix), do: SharedLibrary.get(:palette, id, origin, site, prefix)
  def list_available_palettes(site, prefix), do: SharedLibrary.list_available(:palette, site, prefix)
  def list_palettes_for_rendering(site, prefix), do: SharedLibrary.list_for_rendering(:palette, site, prefix)
end
