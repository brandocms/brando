defmodule Brando.Sites.GlobalsTest do
  use ExUnit.Case
  use Brando.ConnCase
  use BrandoIntegration.TestCase

  alias Brando.Factory

  setup do
    ExMachina.Sequence.reset()
  end

  test "get_global" do
    params = Factory.params_for(:global_category) |> Brando.Utils.map_from_struct()
    Brando.Globals.create_global_category(params, :system)
    assert Brando.Cache.Globals.update({:ok, :dummy}) === {:ok, :dummy}
    assert Brando.Globals.get_global("non_existing") == {:error, {:global, :not_found}}

    {:ok, global} = Brando.Globals.get_global("system.key-0")
    assert global.key == "key-0"
  end

  test "get_global!" do
    params = Factory.params_for(:global_category) |> Brando.Utils.map_from_struct()
    Brando.Globals.create_global_category(params, :system)

    assert Brando.Cache.Globals.update({:ok, :dummy}) === {:ok, :dummy}
    assert Brando.Globals.get_global!("non_existing") == ""

    global = Brando.Globals.get_global!("system.key-0")
    assert global.key == "key-0"
  end

  test "render_global" do
    params = Factory.params_for(:global_category) |> Brando.Utils.map_from_struct()
    Brando.Globals.create_global_category(params, :system)

    assert Brando.Cache.Globals.update({:ok, :dummy}) === {:ok, :dummy}
    assert Brando.Globals.render_global("non_existing") == ""

    global = Brando.Globals.render_global("system.key-0")
    assert global.key == "key-0"
  end

  test "get_global_category" do
    params = Factory.params_for(:global_category) |> Brando.Utils.map_from_struct()
    {:ok, c1} = Brando.Globals.create_global_category(params, :system)

    assert Brando.Globals.get_global_category(999_999_999) ==
             {:error, {:global_category, :not_found}}

    {:ok, c2} = Brando.Globals.get_global_category(c1.id)
    assert c2.id == c1.id
  end

  test "create_global_category" do
    {:ok, c1} = Brando.Globals.create_global_category(%{label: "System", key: "system"}, :system)
    assert c1.label == "System"
  end

  test "update_global_category" do
    {:ok, c1} = Brando.Globals.create_global_category(%{label: "System", key: "system"}, :system)
    assert c1.label == "System"
    {:ok, c2} = Brando.Globals.update_global_category(c1.id, %{label: "New"}, :system)
    assert c2.label == "New"
    refute c1 == c2
  end
end
