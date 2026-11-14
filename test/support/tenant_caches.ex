defmodule Brando.TenantCaches do
  @moduledoc """
  Forgets what a test cached under tenant prefixes: the site caches
  (identity, SEO, navigation, their generations and freshness tokens) and the
  query cache rendering fills, all keyed `{:tenant, prefix, _}`. Rows the
  sandbox rolls back stay cached otherwise, for the next test that uses the
  same prefix.
  """

  @spec clear([String.t()]) :: :ok
  def clear(prefixes) do
    for cache <- [:cache, :query], prefix <- prefixes do
      cache
      |> Cachex.stream!([{{:entry, {:tenant, prefix, :_}, :_, :_, :_}, [], [:"$_"]}])
      |> Enum.each(fn {:entry, key, _, _, _} -> Cachex.del(cache, key) end)
    end

    :ok
  end

  @doc "How many entries the caches hold under `prefixes`."
  @spec count([String.t()]) :: non_neg_integer()
  def count(prefixes) do
    for cache <- [:cache, :query], prefix <- prefixes, reduce: 0 do
      total -> total + Enum.count(Cachex.stream!(cache, [{{:entry, {:tenant, prefix, :_}, :_, :_, :_}, [], [true]}]))
    end
  end
end
