defmodule Brando.Villain.ContextCache do
  @moduledoc """
  Read-only access to the cached data included in Villain render contexts.

  Cache refresh modules depend on the full Sites and Navigation contexts. This
  facade keeps the common render path independent of those mutation contexts,
  while retaining the existing lazy warm-up behavior for identity and globals.
  """

  alias Brando.Cache

  @identity_cache Module.concat(["Brando", "Cache", "Identity"])
  @globals_cache Module.concat(["Brando", "Cache", "Globals"])

  @doc """
  Gets the cached identity for `language`, warming the cache when necessary.
  """
  @spec identity(binary()) :: map()
  def identity(language) do
    identity_map = Cache.get(:identity) || @identity_cache.set()
    Map.get(identity_map, language, %{})
  end

  @doc """
  Gets the cached global sets for `language`, warming the cache when necessary.
  """
  @spec globals(binary()) :: map()
  def globals(language) do
    globals_map = Cache.get(:globals) || @globals_cache.set()
    Map.get(globals_map || %{}, language, %{})
  end

  @doc """
  Gets the cached navigation tree.
  """
  @spec navigation() :: map() | nil
  def navigation, do: Cache.get(:navigation)
end
