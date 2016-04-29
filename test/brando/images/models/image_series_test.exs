defmodule Brando.Integration.ImageSeriesTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase

  alias Brando.ImageSeries
  alias Brando.Factory

  setup do
    user = Factory.create(:user)
    category = Factory.create(:image_category, creator: user)
    series = Factory.create(:image_series, creator: user, image_category: category)
    {:ok, %{user: user, category: category, series: series}}
  end

  test "by_category_id", %{category: category} do
    q = ImageSeries.by_category_id(category.id)
    result = Brando.repo.all(q)
    assert length(result) == 1
    series = List.first(result)
    assert series.name == "Series name"
  end

  test "meta", %{series: series} do
    assert ImageSeries.__name__(:singular) == "imageserie"
    assert ImageSeries.__name__(:plural) == "imageseries"
    assert ImageSeries.__repr__(series) == "Series name – 0 image(s)."
  end
end
