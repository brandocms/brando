defmodule Brando.Integration.ImageSeriesTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase

  alias Brando.Factory
  alias Brando.ImageSeries

  setup do
    user = Factory.insert(:user)
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
    cs = ImageSeries.changeset(series, :update, %{slug: "abracadabra"})
    assert Ecto.Changeset.get_change(cs, :slug) == "abracadabra"
    cs = ImageSeries.validate_paths(cs)

    assert Ecto.Changeset.get_change(cs, :cfg).upload_path ==
             "portfolio/test-category/abracadabra"
  end
end
