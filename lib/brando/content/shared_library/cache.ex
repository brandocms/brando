defmodule Brando.Content.SharedLibrary.Cache do
  @moduledoc false

  @keys_key {__MODULE__, :keys}
  @fence_key {__MODULE__, :fence}

  def get(site_id, kind) do
    :persistent_term.get(key(site_id, kind), nil)
  end

  def put(site_id, kind, ids) do
    move_fence()
    store(site_id, kind, ids)
  end

  # Stores the IDs `load` reads. A change to the cache (`put/3`,
  # `invalidate/2`) meanwhile moves the fence, and the IDs, which may predate
  # it, are dropped once stored.
  def fill(site_id, kind, load) do
    fence = :persistent_term.get(@fence_key, nil)
    ids = load.()
    store(site_id, kind, ids)
    if :persistent_term.get(@fence_key, nil) != fence, do: :persistent_term.erase(key(site_id, kind))
    MapSet.new(ids)
  end

  def invalidate(site_id, kind) do
    move_fence()
    :persistent_term.erase(key(site_id, kind))
    :ok
  end

  # Another node changed the site's allowlist: `Brando.CacheSync`. The next
  # read loads it again.
  def refresh_node_cache({site_id, kind}), do: invalidate(site_id, kind)

  def clear do
    @keys_key
    |> :persistent_term.get(MapSet.new())
    |> Enum.each(&:persistent_term.erase/1)

    :persistent_term.erase(@keys_key)
    :ok
  end

  defp store(site_id, kind, ids) do
    cache_key = key(site_id, kind)
    :persistent_term.put(cache_key, MapSet.new(ids))

    keys = :persistent_term.get(@keys_key, MapSet.new())
    :persistent_term.put(@keys_key, MapSet.put(keys, cache_key))
    :ok
  end

  # Unique on this node, so a fence never comes back to a value a fill holds
  defp move_fence, do: :persistent_term.put(@fence_key, System.unique_integer([:positive]))

  defp key(site_id, kind), do: {__MODULE__, site_id, kind}
end
