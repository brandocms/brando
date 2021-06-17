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

  def put(key, val, ttl \\ :timer.minutes(15))
  def put(key, val, ttl), do: @cache_module.put(:query, key, val, ttl: ttl)

  def put({:single, src, hash}, val, ttl, id),
    do: @cache_module.put(:query, {:single, src, hash, id}, val, ttl: ttl)

  defp get_from_cache({:single, source, key}), do: find_single_entry(source, key)
  defp get_from_cache(key), do: @cache_module.get(:query, key)

  @spec evict({:ok, map()} | {:error, changeset}) :: {:ok, map()} | {:error, changeset}
  def evict({:ok, entry}) do
    source = entry.__struct__.__schema__(:source)
    perform_eviction(:list, source)
    perform_eviction(:single, source, entry.id)
    {:ok, entry}
  end

  def evict({:error, changeset}), do: {:error, changeset}

  # from insert!, update!, etc.
  def evict(entry) do
    source = entry.__struct__.__schema__(:source)
    perform_eviction(:list, source)
    perform_eviction(:single, source, entry.id)
    entry
  end

  @spec perform_eviction(:list, binary()) :: [:ok]
  defp perform_eviction(:list, schema) do
    ms = [{{:entry, {:list, schema, :_}, :_, :_, :_}, [], [:"$_"]}]

    :query
    |> Cachex.stream!(ms)
    |> Enum.map(fn {_, key, _, _, _} -> Cachex.del(:query, key) end)
  rescue
    Cachex.ExecutionError -> :ok
  end

  @spec perform_eviction(:single, binary(), integer()) :: [:ok]
  defp perform_eviction(:single, schema, id) do
    ms = [{{:entry, {:single, schema, :_, id}, :_, :_, :_}, [], [:"$_"]}]

    :query
    |> Cachex.stream!(ms)
    |> Enum.map(fn {_, key, _, _, _} -> Cachex.del(:query, key) end)
  rescue
    Cachex.ExecutionError -> :ok
  end

  defp find_single_entry(source, key) do
    ms = [{{:entry, {:single, source, key, :_}, :_, :_, :_}, [], [:"$_"]}]

    :query
    |> Cachex.stream!(ms)
    |> Enum.map(fn {_, _, _, _, entry} -> entry end)
    |> List.first()
    |> case do
      nil -> {:error, nil}
      entry -> {:ok, entry}
    end
  end
end
