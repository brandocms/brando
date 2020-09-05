defmodule BrandoIntegration.ImageSeriesTest do
  use ExUnit.Case
  use Brando.ConnCase
  use BrandoIntegration.TestCase

  alias Brando.Factory
  alias Brando.ImageSeries

  setup do
    user = Factory.insert(:random_user)
    category = Factory.insert(:image_category, creator: user)
    series = Factory.insert(:image_series, creator: user, image_category: category)

    {:ok, %{user: user, category: category, series: series}}
  end

  test "by_category_id", %{category: category} do
    q = ImageSeries.by_category_id(category.id)
    result = Brando.repo().all(q)
    assert length(result) == 1
    series = List.first(result)
    assert series.name == "Series name"
  end

  test "validate_paths", %{series: series} do
    cs = ImageSeries.changeset(series, %{slug: "abracadabra"})
    assert Ecto.Changeset.get_change(cs, :slug) == "abracadabra"
    cs = ImageSeries.validate_paths(cs)

    assert Ecto.Changeset.get_change(cs, :cfg).upload_path ==
             "portfolio/test-category/abracadabra"
  end

  test "get" do
    c1 = Factory.insert(:image_series, slug: "test")
    {:ok, c2} = Brando.Images.get_image_series(%{matches: [{:slug, "test"}]})
    assert c1.id == c2.id
  end
end
