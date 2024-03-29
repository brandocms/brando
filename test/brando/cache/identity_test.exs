defmodule Brando.Cache.IdentityTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  use BrandoIntegration.TestCase

  test "get and update" do
    identity = Brando.Cache.Identity.get("en")
    assert Map.get(identity, :name) == "Organization name"

    new_identity = Map.put(identity, :name, "Strawberry Alarm Clock")
    assert Brando.Cache.Identity.update({:ok, new_identity}) == {:ok, new_identity}

    identity = Brando.Cache.Identity.get("en")
    assert Map.get(identity, :name, "Strawberry Alarm Clock")
  end
end
