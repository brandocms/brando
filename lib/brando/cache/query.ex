defmodule Brando.Cache.Query do
  @moduledoc """
  Interactions with query cache
  """
  @type changeset :: Ecto.Changeset.t()
  @cache_module Application.compile_env(:brando, :cache_module, Cachex)

  @doc """
  Hashes a query key into the canonical cache-key representation.
  """
  @spec hash_query({atom(), binary(), term()}) :: {atom(), binary(), binary()}
  def hash_query({query_type, query_name, _} = query_key) do
    {query_type, query_name, Base.encode16(<<:erlang.phash2(Jason.encode!(query_key))::size(32)>>)}
  end

  @doc """
  Looks up a query cache entry and describes how a miss should be stored.
  """
  @spec try_cache(term(), false | nil | true | {:ttl, term()}) ::
          {:hit, term()} | {:miss, term(), term()} | :no_cache
  def try_cache(query_key, cache_opts)
  def try_cache(_query_key, nil), do: :no_cache
  def try_cache(_query_key, false), do: :no_cache

  def try_cache(query_key, true), do: try_cache(query_key, {:ttl, :timer.minutes(15)})

  def try_cache(query_key, {:ttl, ttl}) do
    cache_key = hash_query(query_key)

    case get(cache_key) do
      nil -> {:miss, cache_key, ttl}
      result -> {:hit, result}
    end
  end

  @spec get(any) :: any
  def get(key) do
    case get_from_cache(key) do
      {:ok, val} -> val
      {:error, _} -> nil
    end
  end

  def put(key, val, ttl \\ :timer.minutes(15))
  def put(key, val, ttl), do: @cache_module.put(:query, key, val, expire: ttl)

  def put({:single, src, hash}, val, ttl, id), do: @cache_module.put(:query, {:single, src, hash, id}, val, expire: ttl)

  defp get_from_cache({:single, source, key}), do: find_single_entry(source, key)
  defp get_from_cache(key), do: @cache_module.get(:query, key)

  @spec evict({:ok, map()} | {:error, changeset}) :: {:ok, map()} | {:error, changeset}
  def evict({:ok, entry}) when is_map(entry) do
    source = entry.__struct__.__schema__(:source)

    perform_eviction(:list, source)
    perform_eviction(:single, source, entry.id)

    # TODO: a declarative way to specify any related entries to evict?
    # Evict parent page if applicable
    if Map.get(entry, :parent_id) do
      perform_eviction(:single, source, entry.parent_id)
    end

    {:ok, entry}
  end

  def evict({:error, changeset}), do: {:error, changeset}

  # from insert!, update!, etc.
  def evict(entry) when is_map(entry) do
    source = entry.__struct__.__schema__(:source)
    perform_eviction(:list, source)
    perform_eviction(:single, source, entry.id)
    entry
  end

  def evict_schema(schema) do
    source = schema.__schema__(:source)
    perform_eviction(:list, source)
    schema
  end

  def evict_entry(schema, id) do
    source = schema.__schema__(:source)
    perform_eviction(:single, source, id)
    schema
  end

  @spec perform_eviction(:list, binary()) :: [:ok]
  defp perform_eviction(:list, schema) do
    ms = [{{:entry, {:list, schema, :_}, :_, :_, :_}, [], [:"$_"]}]

    :query
    |> Cachex.stream!(ms)
    |> Enum.map(fn {_, key, _, _, _} -> Cachex.del(:query, key) end)
  rescue
    Cachex.Error -> :ok
  end

  @spec perform_eviction(:single, binary(), integer()) :: [:ok]
  defp perform_eviction(:single, schema, id) do
    ms = [{{:entry, {:single, schema, :_, id}, :_, :_, :_}, [], [:"$_"]}]

    :query
    |> Cachex.stream!(ms)
    |> Enum.map(fn {_, key, _, _, _} -> Cachex.del(:query, key) end)
  rescue
    Cachex.Error -> :ok
  end

  defp find_single_entry(source, key) do
    ms = [{{:entry, {:single, source, key, :_}, :_, :_, :_}, [], [:"$_"]}]

    :query
    |> Cachex.stream!(ms)
    |> Enum.map(fn {:entry, _key_tuple, entry, _ts, _exp} -> entry end)
    |> List.first()
    |> case do
      nil -> {:error, nil}
      entry -> {:ok, entry}
    end
  end
end
