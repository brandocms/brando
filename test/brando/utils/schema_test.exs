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

    _ = Factory.insert(:image_category, name: "test", slug: "test")
    _ = Factory.insert(:image_category, name: "test", slug: "test-1")
    _ = Factory.insert(:image_category, name: "test", slug: "test-2")
    _ = Factory.insert(:image_category, name: "test", slug: "test-3")
    _ = Factory.insert(:image_category, name: "test", slug: "test-4")
    _ = Factory.insert(:image_category, name: "test", slug: "test-5")
    _ = Factory.insert(:image_category, name: "test", slug: "test-6")
    _ = Factory.insert(:image_category, name: "test", slug: "test-7")
    _ = Factory.insert(:image_category, name: "test", slug: "test-8")
    _ = Factory.insert(:image_category, name: "test", slug: "test-9")

    {:ok, c0} = Brando.Images.create_category(%{name: "test", slug: "test"}, u1)

    assert c0.slug == "test-10"

    _ = Factory.insert(:image_category, name: "test", slug: "test-11")
    _ = Factory.insert(:image_category, name: "test", slug: "test-12")
    _ = Factory.insert(:image_category, name: "test", slug: "test-13")
    _ = Factory.insert(:image_category, name: "test", slug: "test-14")
    _ = Factory.insert(:image_category, name: "test", slug: "test-15")
    _ = Factory.insert(:image_category, name: "test", slug: "test-16")
    _ = Factory.insert(:image_category, name: "test", slug: "test-17")
    _ = Factory.insert(:image_category, name: "test", slug: "test-18")
    _ = Factory.insert(:image_category, name: "test", slug: "test-19")
    _ = Factory.insert(:image_category, name: "test", slug: "test-20")
    _ = Factory.insert(:image_category, name: "test", slug: "test-21")
    _ = Factory.insert(:image_category, name: "test", slug: "test-22")
    _ = Factory.insert(:image_category, name: "test", slug: "test-23")
    _ = Factory.insert(:image_category, name: "test", slug: "test-24")
    _ = Factory.insert(:image_category, name: "test", slug: "test-25")
    _ = Factory.insert(:image_category, name: "test", slug: "test-26")
    _ = Factory.insert(:image_category, name: "test", slug: "test-27")
    _ = Factory.insert(:image_category, name: "test", slug: "test-28")
    _ = Factory.insert(:image_category, name: "test", slug: "test-29")
    _ = Factory.insert(:image_category, name: "test", slug: "test-30")

    {:error, changeset} = Brando.Images.create_category(%{name: "test", slug: "test"}, u1)

    assert changeset.errors == [slug: {"Klarte ikke finne en ledig verdi for feltet", []}]
  end
end
