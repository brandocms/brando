defmodule Brando.Cache.GlobalsTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase

  alias Brando.Factory

  test "set and get" do
    assert Brando.Cache.Globals.set()
    assert Brando.Cache.Globals.get() == %{}

    globals = Factory.build_list(2, :global)
    Factory.insert(:global_category, globals: globals)
    assert Brando.Cache.Globals.update({:ok, :dummy}) === {:ok, :dummy}

    global_map = Brando.Cache.Globals.get()
    assert Map.keys(global_map) === ["system.key-0", "system.key-1"]
    assert get_in(global_map, [Access.key("system.key-0"), Access.key(:key)]) === "key-0"
    assert get_in(global_map, [Access.key("system.key-1"), Access.key(:key)]) === "key-1"
  end
end
