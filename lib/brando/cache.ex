defmodule Brando.Cache do
  @moduledoc """

  """
  @cache_module Application.get_env(:brando, :cache_module, Cachex)

  @spec get(atom) :: any
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

  defp get_from_cache(key) do
    @cache_module.get(:cache, key)
  end
end
