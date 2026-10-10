defmodule Brando.Cache.Query do
  @moduledoc """
  Interactions with query cache

  ## Evict after commit

  `evict/1`, `evict_entry/2` and `evict_schema/1` (and so `Brando.Query`'s
  `insert/2`, `update/2` and `delete/1`) evict at once. Inside a transaction
  (with group authorization a generated context mutation always runs in one)
  that is before the commit, and a read by another process in between still
  sees the old row and caches it again, so they also evict once the
  transaction has committed: automatically, once per cache entry however
  many writes the transaction makes, under the tenant prefix of the write
  (`Brando.Repo.after_commit/2`). Only a transaction begun with
  `Brando.Repo.transaction/2` holds that back; inside one begun on the repo
  itself it runs at once. The `{:mutation, ...}` broadcast of a generated
  create, delete or changeset update also goes out after the commit (an
  update by id sends none).
  """
  @type changeset :: Ecto.Changeset.t()
  @cache_module Application.compile_env(:brando, :cache_module, Cachex)

  @doc """
  Hashes a query key into the canonical cache-key representation.
  """
  @spec hash_query({atom(), binary(), term()}) :: term()
  def hash_query({query_type, query_name, _} = query_key) do
    key = {query_type, query_name, Base.encode16(<<:erlang.phash2(Jason.encode!(query_key))::size(32)>>)}
    Brando.Tenant.cache_key(key)
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

  def put({:single, src, hash}, val, ttl, id),
    do: @cache_module.put(:query, {:single, src, hash, id}, val, expire: ttl)

  def put({:tenant, prefix, {:single, src, hash}}, val, ttl, id),
    do: @cache_module.put(:query, {:tenant, prefix, {:single, src, hash, id}}, val, expire: ttl)

  defp get_from_cache({:single, source, key}), do: find_single_entry(source, key)
  defp get_from_cache({:tenant, prefix, {:single, source, key}}), do: find_single_entry(source, key, prefix)
  defp get_from_cache(key), do: @cache_module.get(:query, key)

  @spec evict({:ok, map()} | {:error, changeset}) :: {:ok, map()} | {:error, changeset}
  def evict({:ok, entry}) when is_map(entry) do
    source = entry.__struct__.__schema__(:source)

    evict_list(source)
    evict_single(source, entry.id)

    # TODO: a declarative way to specify any related entries to evict?
    # Evict parent page if applicable
    if parent_id = Map.get(entry, :parent_id) do
      evict_single(source, parent_id)
    end

    {:ok, entry}
  end

  def evict({:error, changeset}), do: {:error, changeset}

  # from insert!, update!, etc.
  def evict(entry) when is_map(entry) do
    source = entry.__struct__.__schema__(:source)
    evict_list(source)
    evict_single(source, entry.id)
    entry
  end

  def evict_schema(schema) do
    evict_list(schema.__schema__(:source))
    schema
  end

  def evict_entry(schema, id) do
    evict_single(schema.__schema__(:source), id)
    schema
  end

  defp evict_list(source), do: evict_committed({:list, source}, fn -> perform_eviction(:list, source) end)

  defp evict_single(source, id),
    do: evict_committed({:single, source, id}, fn -> perform_eviction(:single, source, id) end)

  # Inside a transaction, evicts now, so this process reads its own write,
  # and again once the transaction has committed: another process reading
  # in between still sees the old row and caches it again. The second runs
  # under the tenant prefix of the write, which may be gone by then, and
  # once per cache entry however many writes the transaction makes.
  defp evict_committed(key, evict) do
    evict.()

    if Brando.Repo.repo().in_transaction?() do
      prefix = Brando.Tenant.current_prefix()
      Brando.Repo.after_commit({__MODULE__, prefix, key}, fn -> Brando.Tenant.with_prefix(prefix, evict) end)
    end

    :ok
  end

  @spec perform_eviction(:list, binary()) :: [:ok]
  defp perform_eviction(:list, schema) do
    key_pattern = scoped_pattern({:list, schema, :_})
    ms = [{{:entry, key_pattern, :_, :_, :_}, [], [:"$_"]}]

    :query
    |> Cachex.stream!(ms)
    |> Enum.map(fn {_, key, _, _, _} -> Cachex.del(:query, key) end)
  rescue
    Cachex.Error -> :ok
  end

  @spec perform_eviction(:single, binary(), integer()) :: [:ok]
  defp perform_eviction(:single, schema, id) do
    key_pattern = scoped_pattern({:single, schema, :_, id})
    ms = [{{:entry, key_pattern, :_, :_, :_}, [], [:"$_"]}]

    :query
    |> Cachex.stream!(ms)
    |> Enum.map(fn {_, key, _, _, _} -> Cachex.del(:query, key) end)
  rescue
    Cachex.Error -> :ok
  end

  defp find_single_entry(source, key, prefix \\ nil) do
    key_pattern =
      if prefix,
        do: {:tenant, prefix, {:single, source, key, :_}},
        else: {:single, source, key, :_}

    ms = [{{:entry, key_pattern, :_, :_, :_}, [], [:"$_"]}]

    :query
    |> Cachex.stream!(ms)
    |> Enum.map(fn {:entry, _key_tuple, entry, _ts, _exp} -> entry end)
    |> List.first()
    |> case do
      nil -> {:error, nil}
      entry -> {:ok, entry}
    end
  end

  defp scoped_pattern(key_pattern) do
    case Brando.Tenant.current_prefix() do
      nil -> key_pattern
      prefix -> {:tenant, prefix, key_pattern}
    end
  end
end
