defmodule Brando.Cache do
  @moduledoc """

  """
  @cache_module Application.get_env(:brando, :cache_module, Cachex)

  @spec get(atom | binary) :: any
  def get(key) do
    case get_from_cache(key) do
      {:ok, val} -> val
      {:error, _} -> nil
    end
  end

  @spec get(atom, atom) :: any
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

  defp get_from_cache(key) do
    @cache_module.get(:cache, key)
  end
end
