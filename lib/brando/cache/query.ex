defmodule Brando.Cache.Query do
  @moduledoc """
  Interactions with query cache
  """
  @type changeset :: Ecto.Changeset.t()
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

  @spec evict({:ok, map()} | {:error, changeset}) :: {:ok, map()} | {:error, changeset}
  def evict({:ok, entry}) do
    source = entry.__struct__.__schema__(:source)
    perform_eviction(:list, source)
    {:ok, entry}
  end

  def evict({:error, changeset}), do: {:error, changeset}

  # from insert!, update!, etc.
  def evict(entry) do
    source = entry.__struct__.__schema__(:source)
    perform_eviction(:list, source)
    entry
  end

  @spec perform_eviction(:list | :single, binary()) :: [:ok]
  defp perform_eviction(type, schema) do
    ms = [{{:entry, {type, schema, :_}, :_, :_, :_}, [], [:"$_"]}]

    :query
    |> Cachex.stream!(ms)
    |> Enum.map(fn {_, key, _, _, _} -> Cachex.del(:query, key) end)
  end
end
