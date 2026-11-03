defmodule Brando.Villain.ContextCache do
  @moduledoc """
  Read-only access to the cached data included in Villain render contexts.

  Cache refresh modules depend on the full Sites and Navigation contexts. This
  facade keeps the common render path independent of those mutation contexts,
  while retaining the lazy warm-up behavior for identity, globals and navigation.
  """

  alias Brando.Cache
  alias Brando.Villain.RenderScope

  @identity_cache Module.concat(["Brando", "Cache", "Identity"])
  @globals_cache Module.concat(["Brando", "Cache", "Globals"])
  @navigation_cache Module.concat(["Brando", "Cache", "Navigation"])

  @doc """
  Gets the cached identity for `language`, warming the cache when necessary.
  """
  @spec identity(binary()) :: map()
  def identity(language) do
    RenderScope.fetch({__MODULE__, :identity, language}, fn ->
      identity_map = Cache.get_site(:identity) || @identity_cache.set()
      Map.get(identity_map, language, %{})
    end)
  end

  @doc """
  Gets the cached global sets for `language`, warming the cache when necessary.
  """
  @spec globals(binary()) :: map()
  def globals(language) do
    RenderScope.fetch({__MODULE__, :globals, language}, fn ->
      globals_map = Cache.get_site(:globals) || @globals_cache.set()
      Map.get(globals_map || %{}, language, %{})
    end)
  end

  @doc """
  Gets the cached navigation tree, warming the cache when necessary.
  """
  @spec navigation() :: map() | nil
  def navigation, do: RenderScope.fetch({__MODULE__, :navigation}, &@navigation_cache.get/0)
end
