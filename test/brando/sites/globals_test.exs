defmodule Brando.Sites.GlobalsTest do
  use ExUnit.Case
  use Brando.ConnCase
  use BrandoIntegration.TestCase

  alias Brando.Factory

  setup do
    ExMachina.Sequence.reset()
    user = Factory.insert(:user)
    {:ok, %{user: user}}
  end

  test "get_global_path", %{user: user} do
    params =
      Factory.params_for(:global_set, creator_id: user.id) |> Brando.Utils.map_from_struct()

    Brando.Sites.create_global_set(params, :system)
    assert Brando.Cache.Globals.update({:ok, :dummy}) === {:ok, :dummy}
    assert Brando.Sites.get_global_path("non_existing") == {:error, {:global, :not_found}}

    {:ok, global} = Brando.Sites.get_global_path("en.system.key-0")
    assert global.key == "key-0"
  end

  test "get_global_path!", %{user: user} do
    params =
      Factory.params_for(:global_set, creator_id: user.id) |> Brando.Utils.map_from_struct()

    Brando.Sites.create_global_set(params, :system)

    assert Brando.Cache.Globals.update({:ok, :dummy}) === {:ok, :dummy}
    assert Brando.Sites.get_global_path!("non_existing") == ""

    global = Brando.Sites.get_global_path!("en.system.key-0")
    assert global.key == "key-0"
  end

  test "get_global_set", %{user: user} do
    params =
      Factory.params_for(:global_set, creator_id: user.id) |> Brando.Utils.map_from_struct()

    {:ok, c1} = Brando.Sites.create_global_set(params, :system)

    assert Brando.Sites.get_global_set(999_999_999) ==
             {:error, {:global_set, :not_found}}

    {:ok, c2} = Brando.Sites.get_global_set(c1.id)
    assert c2.id == c1.id
  end

  test "create_global_set", %{user: user} do
    {:ok, c1} =
      Brando.Sites.create_global_set(
        %{label: "System", key: "system", language: "en"},
        user
      )

    assert c1.label == "System"
  end

  test "update_global_set", %{user: user} do
    {:ok, c1} =
      Brando.Sites.create_global_set(
        %{label: "System", key: "system", language: "en"},
        user
      )

    assert c1.label == "System"
    {:ok, c2} = Brando.Sites.update_global_set(c1.id, %{label: "New"}, user)
    assert c2.label == "New"
    refute c1 == c2
  end
end
