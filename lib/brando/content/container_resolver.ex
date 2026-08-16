defmodule Brando.Content.ContainerResolver do
  @moduledoc "Tenant-first resolver for shared and site-specific containers."

  alias Brando.Content.SharedLibrary

  def get_container(id, site, prefix), do: SharedLibrary.get(:container, id, site, prefix)
  def get_container(id, origin, site, prefix), do: SharedLibrary.get(:container, id, origin, site, prefix)
  def list_available_containers(site, prefix), do: SharedLibrary.list_available(:container, site, prefix)
  def list_containers_for_rendering(site, prefix), do: SharedLibrary.list_for_rendering(:container, site, prefix)
end
