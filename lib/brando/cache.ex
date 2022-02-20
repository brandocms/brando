defmodule Brando.Cache do
  @moduledoc """
  Interface for the main cache module
  """
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
    @cache_module.put(:cache, key, val)
  end

  def put(key, val, ttl) do
    @cache_module.put(:cache, key, val, ttl: ttl)
  end

  def del(key) do
    @cache_module.del(:cache, key)
  end

  defp get_from_cache(key) do
    @cache_module.get(:cache, key)
  end
end
