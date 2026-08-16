defmodule Brando.Content.SharedLibrary.Cache do
  @moduledoc false

  @keys_key {__MODULE__, :keys}

  def get(site_id, kind) do
    :persistent_term.get(key(site_id, kind), nil)
  end

  def put(site_id, kind, ids) do
    cache_key = key(site_id, kind)
    :persistent_term.put(cache_key, MapSet.new(ids))

    keys = :persistent_term.get(@keys_key, MapSet.new())
    :persistent_term.put(@keys_key, MapSet.put(keys, cache_key))
    :ok
  end

  def invalidate(site_id, kind) do
    :persistent_term.erase(key(site_id, kind))
    :ok
  end

  def clear do
    @keys_key
    |> :persistent_term.get(MapSet.new())
    |> Enum.each(&:persistent_term.erase/1)

    :persistent_term.erase(@keys_key)
    :ok
  end

  defp key(site_id, kind), do: {__MODULE__, site_id, kind}
end
