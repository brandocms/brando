defmodule Brando.Cache.GlobalsTest do
  use ExUnit.Case
  use Brando.ConnCase
  use BrandoIntegration.TestCase

  alias Brando.Sites
  alias Brando.Factory

  setup do
    ExMachina.Sequence.reset()
  end

  test "set and get" do
    assert Brando.Cache.Sites.set()
    assert Brando.Cache.Sites.get() == %{}

    category_params =
      :global_set
      |> Factory.params_for()
      |> Brando.Utils.map_from_struct()

    {:ok, _category} = Sites.create_global_set(category_params, :system)

    assert Brando.Cache.Sites.update({:ok, :dummy}) === {:ok, :dummy}

    global_map = Brando.Cache.Sites.get()
    assert Map.keys(global_map) === ["system"]

    assert get_in(global_map, [Access.key("system"), Access.key("key-0"), Access.key(:key)]) ===
             "key-0"

    assert get_in(global_map, [Access.key("system"), Access.key("key-1"), Access.key(:key)]) ===
             "key-1"
  end
end
