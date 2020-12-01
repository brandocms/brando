defmodule Brando.Cache.Query do
  @moduledoc """
  Interactions with query cache
  """
  @cache_module Application.get_env(:brando, :cache_module, Cachex)

  @spec get(any) :: any
  def get(key) do
    case get_from_cache(key) do
      {:ok, val} -> val
      {:error, _} -> nil
    end
  end

  def put(key, val, ttl \\ :timer.minutes(15)), do: @cache_module.put(:query, key, val, ttl: ttl)
  defp get_from_cache(key), do: @cache_module.get(:query, key)
end
