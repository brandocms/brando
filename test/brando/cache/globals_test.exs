defmodule Brando.Cache.GlobalsTest do
  use ExUnit.Case
  use Brando.ConnCase
  use BrandoIntegration.TestCase

  alias Brando.Globals
  alias Brando.Factory

  setup do
    ExMachina.Sequence.reset()
  end

  test "set and get" do
    assert Brando.Cache.Globals.set()
    assert Brando.Cache.Globals.get() == %{}

    category_params =
      :global_category
      |> Factory.params_for()
      |> Brando.Utils.map_from_struct()

    {:ok, _category} = Globals.create_global_category(category_params, :system)

    assert Brando.Cache.Globals.update({:ok, :dummy}) === {:ok, :dummy}

    global_map = Brando.Cache.Globals.get()
    assert Map.keys(global_map) === ["system"]

    assert get_in(global_map, [Access.key("system"), Access.key("key-0"), Access.key(:key)]) ===
             "key-0"

    assert get_in(global_map, [Access.key("system"), Access.key("key-1"), Access.key(:key)]) ===
             "key-1"
  end
end
