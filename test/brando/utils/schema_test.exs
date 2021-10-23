defmodule Brando.Utils.SchemaTest do
  use ExUnit.Case
  use Brando.ConnCase
  use BrandoIntegration.TestCase
  use Plug.Test

  alias Brando.Factory
  alias Brando.Utils

  test "update_field/2" do
    user = Factory.insert(:random_user)
    assert {:ok, schema} = Utils.Schema.update_field(user, name: "James Bond")
    assert schema.name == "James Bond"
  end

  test "put_slug pass" do
    assert Utils.Schema.put_slug(%{}) == %{}
  end

  test "avoid_field_collision pass" do
    assert Utils.Schema.avoid_field_collision(%{}, nil) == %{}
  end

  test "avoid_field_collision" do
    u1 = Factory.insert(:random_user)

    prm = [title: "test", status: :published, template: "default.html", language: "en"]

    _ = Factory.insert(:page, prm ++ [uri: "test"])
    _ = Factory.insert(:page, prm ++ [uri: "test-1"])
    _ = Factory.insert(:page, prm ++ [uri: "test-2"])
    _ = Factory.insert(:page, prm ++ [uri: "test-3"])
    _ = Factory.insert(:page, prm ++ [uri: "test-4"])
    _ = Factory.insert(:page, prm ++ [uri: "test-5"])
    _ = Factory.insert(:page, prm ++ [uri: "test-6"])
    _ = Factory.insert(:page, prm ++ [uri: "test-7"])
    _ = Factory.insert(:page, prm ++ [uri: "test-8"])
    _ = Factory.insert(:page, prm ++ [uri: "test-9"])

    {:ok, c0} = Brando.Pages.create_page((prm ++ [uri: "test"]) |> Enum.into(%{}), u1)

    assert c0.uri == "test-10"

    _ = Factory.insert(:page, prm ++ [uri: "test-11"])
    _ = Factory.insert(:page, prm ++ [uri: "test-12"])
    _ = Factory.insert(:page, prm ++ [uri: "test-13"])
    _ = Factory.insert(:page, prm ++ [uri: "test-14"])
    _ = Factory.insert(:page, prm ++ [uri: "test-15"])
    _ = Factory.insert(:page, prm ++ [uri: "test-16"])
    _ = Factory.insert(:page, prm ++ [uri: "test-17"])
    _ = Factory.insert(:page, prm ++ [uri: "test-18"])
    _ = Factory.insert(:page, prm ++ [uri: "test-19"])
    _ = Factory.insert(:page, prm ++ [uri: "test-20"])
    _ = Factory.insert(:page, prm ++ [uri: "test-21"])
    _ = Factory.insert(:page, prm ++ [uri: "test-22"])
    _ = Factory.insert(:page, prm ++ [uri: "test-23"])
    _ = Factory.insert(:page, prm ++ [uri: "test-24"])
    _ = Factory.insert(:page, prm ++ [uri: "test-25"])
    _ = Factory.insert(:page, prm ++ [uri: "test-26"])
    _ = Factory.insert(:page, prm ++ [uri: "test-27"])
    _ = Factory.insert(:page, prm ++ [uri: "test-28"])
    _ = Factory.insert(:page, prm ++ [uri: "test-29"])
    _ = Factory.insert(:page, prm ++ [uri: "test-30"])

    {:error, changeset} = Brando.Pages.create_page((prm ++ [uri: "test"]) |> Enum.into(%{}), u1)

    assert changeset.errors == [uri: {"Could not find available field value", []}]
  end
end
