defmodule Brando.Content.ModuleResolver do
  @moduledoc "Tenant-first resolver for shared and site-specific modules."

  alias Brando.Content.SharedLibrary

  def get_module(id, site, prefix), do: SharedLibrary.get(:module, id, site, prefix)
  def get_module(id, origin, site, prefix), do: SharedLibrary.get(:module, id, origin, site, prefix)
  def list_available_modules(site, prefix), do: SharedLibrary.list_available(:module, site, prefix)
  def list_modules_for_rendering(site, prefix), do: SharedLibrary.list_for_rendering(:module, site, prefix)
end
