defmodule Brando.Villain.ContextCacheTest do
  use ExUnit.Case, async: false

  alias Brando.Cache
  alias Brando.Villain.ContextCache

  setup do
    previous_identity = Cache.get(:identity)
    previous_globals = Cache.get(:globals)
    previous_navigation = Cache.get(:navigation)

    on_exit(fn ->
      restore(:identity, previous_identity)
      restore(:globals, previous_globals)
      restore(:navigation, previous_navigation)
    end)

    :ok
  end

  test "reads render-context data without loading mutation contexts" do
    Cache.put(:identity, %{"en" => %{title: "Brando"}}, :infinite)
    Cache.put(:globals, %{"en" => %{"system" => %{}}}, :infinite)
    Cache.put(:navigation, %{"main" => %{}}, :infinite)

    assert ContextCache.identity("en") == %{title: "Brando"}
    assert ContextCache.identity("no") == %{}
    assert ContextCache.globals("en") == %{"system" => %{}}
    assert ContextCache.globals("no") == %{}
    assert ContextCache.navigation() == %{"main" => %{}}
  end

  defp restore(key, nil), do: Cache.del(key)
  defp restore(key, value), do: Cache.put(key, value, :infinite)
end
