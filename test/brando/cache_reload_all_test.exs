defmodule Brando.CacheReloadAllTest do
  # Uses the global caches.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  setup do
    preserve_cache([:identity, :seo, :globals, :palettes, :palettes_css, :navigation])
  end

  test "reload_all/0 replaces stale identity and globals caches, and empties the query cache" do
    Brando.Cache.put(:identity, :stale, :infinite)
    Brando.Cache.put(:globals, :stale, :infinite)
    Cachex.put(:query, {:test, :entry}, :stale)

    assert :ok = Brando.Cache.reload_all()

    assert is_map(Brando.Cache.get(:identity))
    assert is_map(Brando.Cache.get(:globals))
    assert {:ok, nil} = Cachex.get(:query, {:test, :entry})
  end
end
