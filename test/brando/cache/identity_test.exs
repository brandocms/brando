defmodule Brando.Cache.IdentityTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase

  test "get and update" do
    identity = Brando.Cache.Identity.get()
    assert Map.get(identity, :name) == "Organisasjonens navn"

    new_identity = Map.put(identity, :name, "Strawberry Alarm Clock")
    assert Brando.Cache.Identity.update({:ok, new_identity}) == {:ok, new_identity}

    identity = Brando.Cache.Identity.get()
    assert Map.get(identity, :name, "Strawberry Alarm Clock")
  end
end
