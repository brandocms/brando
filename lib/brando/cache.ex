defmodule Brando.Cache do
  @moduledoc """
  Interface for the main cache module
  """
  use Brando.Tracing.Decorator

  @cache_module Application.compile_env(:brando, :cache_module, Cachex)

  @spec get(any) :: any
  def get(key) do
    case get_from_cache(key) do
      {:ok, val} -> val
      {:error, _} -> nil
    end
  end

  @spec get(any, atom) :: any
  def get(key, sub_key) do
    case get_from_cache(key) do
      {:ok, val} -> Map.get(val, sub_key, nil)
      {:error, _} -> nil
    end
  end

  def put(key, var, ttl \\ :timer.minutes(15))

  def put(key, val, :infinite) do
    @cache_module.put(:cache, cache_key(key), val)
  end

  def put(key, val, ttl) do
    @cache_module.put(:cache, cache_key(key), val, expire: ttl)
  end

  def update(key, val) do
    @cache_module.update(:cache, cache_key(key), val)
  end

  def del(key) do
    @cache_module.del(:cache, cache_key(key))
  end

  @doc """
  Empties every cache and reloads the site-wide ones: the query cache (pages,
  fragments, modules, …) and the identity, SEO, globals, palettes and
  navigation caches. For changes made outside this server — a seed, a mix
  task, another node — that it can't have heard about.
  """
  @decorate span("brando.cache.reload_all")
  def reload_all do
    Cachex.clear(:query)
    Brando.Cache.Identity.set()
    Brando.Cache.SEO.set()
    Brando.Cache.Globals.set()
    Brando.Cache.Palettes.set()
    Brando.Cache.Navigation.set()
    :ok
  end

  defp get_from_cache(key) do
    @cache_module.get(:cache, cache_key(key))
  end

  defp cache_key(key), do: Brando.Tenant.cache_key(key)
end
