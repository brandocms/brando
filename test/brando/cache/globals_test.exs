defmodule Brando.Cache.GlobalsTest do
  use ExUnit.Case
  use Brando.ConnCase
  use BrandoIntegration.TestCase

  alias Brando.Sites
  alias Brando.Factory

  setup do
    ExMachina.Sequence.reset()
    user = Factory.insert(:user)
    {:ok, %{user: user}}
  end

  test "set and get", %{user: user} do
    assert Brando.Cache.Globals.set()
    assert Brando.Cache.Globals.get("en") == %{}

    category_params =
      :global_set
      |> Factory.params_for(creator_id: user.id)
      |> Brando.Utils.map_from_struct()

    {:ok, _category} = Sites.create_global_set(category_params, :system)

    assert Brando.Cache.Globals.update({:ok, :dummy}) === {:ok, :dummy}

    global_map = Brando.Cache.Globals.get("en")
    assert Map.keys(global_map) === ["system"]

    assert get_in(global_map, [Access.key("system"), Access.key("key-0"), Access.key(:key)]) ===
             "key-0"

    assert get_in(global_map, [Access.key("system"), Access.key("key-1"), Access.key(:key)]) ===
             "key-1"
  end
end
