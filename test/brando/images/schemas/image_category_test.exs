defmodule BrandoIntegration.ImageCategoryTest do
  use ExUnit.Case
  use Brando.ConnCase
  use BrandoIntegration.TestCase
  alias Brando.Factory

  setup do
    user = Factory.insert(:user)
    category = Factory.insert(:image_category, creator: user)
    series = Factory.insert(:image_series, creator: user, image_category: category)
    {:ok, %{user: user, category: category, series: series}}
  end

  test "get" do
    c1 = Factory.insert(:image_category, slug: "test")
    {:ok, c2} = Brando.Images.get_image_category(%{matches: [{:slug, "test"}]})
    assert c1.id == c2.id
  end
end
