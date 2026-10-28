defmodule Brando.Test.Support do
  @moduledoc false
  import ExUnit.Assertions

  alias Brando.Cache

  def assert_attr(target, attr, value) do
    assert Floki.attribute(target, attr) == value
    target
  end

  @doc """
  Sets `Application.put_env(:brando, key, value)` for one test and restores it
  properly afterwards.

  "Properly" is the whole reason this exists. The obvious restore —

      original = Application.get_env(:brando, key)
      on_exit(fn -> Application.put_env(:brando, key, original) end)

  — stores `nil` when the key was absent, and `nil` is **not** absent:
  `Application.get_env(:brando, key, [])` returns the stored `nil` in preference
  to its own default, so the next caller does `Keyword.get(nil, …)` and gets a
  `FunctionClauseError` instead of the behaviour it configured for. It leaks
  across files, so it surfaces as one test breaking another — which is how it
  was found, at the cost of a cross-file flake.

  `fetch_env/2` distinguishes "absent" from "present and nil", and `delete_env/2`
  is what restores the former.
  """
  def put_test_env(key, value) do
    original = Application.fetch_env(:brando, key)
    Application.put_env(:brando, key, value)

    ExUnit.Callbacks.on_exit(fn ->
      case original do
        {:ok, previous} -> Application.put_env(:brando, key, previous)
        :error -> Application.delete_env(:brando, key)
      end
    end)
  end

  @doc """
  Puts the `Brando.Cache` entries under `keys` back as they were when the test
  exits, or removes them if they were empty.

  The cache outlives the test's database sandbox. Without this, a value a test
  writes (directly, or through a context function that refreshes the cache)
  is read by whichever test runs next. Call it in `setup`, before the test
  writes: `preserve_cache([:identity, :seo])`. The `TestCacheRestore` Credo
  check accepts it as the restore.
  """
  def preserve_cache(keys) do
    for key <- List.wrap(keys) do
      cached = Cache.get(key)
      ExUnit.Callbacks.on_exit(fn -> restore_cache(key, cached) end)
    end

    :ok
  end

  defp restore_cache(key, nil), do: Cache.del(key)
  defp restore_cache(key, cached), do: Cache.put(key, cached, :infinite)

  @doc """
  Puts the query cache entries of `schemas` (lists and single entries, under
  every tenant prefix) back as they were when the test exits, with what was
  left of their TTL, and removes the ones the test added.

  The query cache is `preserve_cache/1`'s counterpart for `Brando.Query`
  results: a test that evicts a schema's entries, or caches rows that roll
  back, calls it in `setup` or before its first query:
  `preserve_query_cache(Brando.Content.Module)`. The `TestCacheRestore` Credo
  check accepts it as the restore.
  """
  def preserve_query_cache(schemas) do
    sources = schemas |> List.wrap() |> Enum.map(& &1.__schema__(:source))
    cached = query_entries(sources)

    ExUnit.Callbacks.on_exit(fn ->
      for entry <- query_entries(sources), do: Cachex.del(:query, elem(entry, 1))
      Cachex.import(:query, cached)
    end)

    :ok
  end

  defp query_entries(sources) do
    {:ok, entries} = Cachex.export(:query)
    Enum.filter(entries, &(query_source(elem(&1, 1)) in sources))
  end

  defp query_source({:tenant, _prefix, key}), do: query_source(key)
  defp query_source({type, source, _hash}) when type in [:list, :single], do: source
  defp query_source({:single, source, _hash, _id}), do: source
  defp query_source(_key), do: nil

  @doc """
  Recursively strips __spark_metadata__ from structs for comparison in tests.

  This is necessary because Spark DSL populates __spark_metadata__ with
  environment-specific file paths that would cause test failures in CI
  or on different developer machines.
  """
  def strip_spark_metadata(struct) when is_struct(struct) do
    struct
    |> Map.from_struct()
    |> Map.delete(:__spark_metadata__)
    |> Enum.map(fn {k, v} -> {k, strip_spark_metadata(v)} end)
    |> Map.new()
    |> then(&struct(struct.__struct__, &1))
  end

  def strip_spark_metadata(list) when is_list(list) do
    Enum.map(list, &strip_spark_metadata/1)
  end

  def strip_spark_metadata(map) when is_map(map) do
    map
    |> Map.delete(:__spark_metadata__)
    |> Enum.map(fn {k, v} -> {k, strip_spark_metadata(v)} end)
    |> Map.new()
  end

  def strip_spark_metadata(other), do: other
end
