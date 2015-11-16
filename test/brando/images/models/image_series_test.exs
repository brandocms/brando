defmodule Brando.Integration.ImageSeriesTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  alias Brando.ImageSeries
  alias Brando.ImageCategory
  alias Brando.Type.ImageConfig

  @params %{sequence: 0, image: %{title: "Title", credits: "credits",
            path: "/tmp/path/to/fake/image.jpg",
            sizes: %{small: "/tmp/path/to/fake/image.jpg",
            thumb: "/tmp/path/to/fake/thumb.jpg"}}}
  @params2 %{sequence: 1, image: %{title: "Title2", credits: "credits2",
             path: "/tmp/path/to/fake/image2.jpg",
             sizes: %{small: "/tmp/path/to/fake/image2.jpg",
             thumb: "/tmp/path/to/fake/thumb2.jpg"}}}
  @series_params %{name: "Series name", slug: "series-name",
                   credits: "Credits", sequence: 0, creator_id: 1}
  @category_params %{cfg: %ImageConfig{}, creator_id: 1,
                     name: "Test Category", slug: "test-category"}

  setup do
    user = Forge.saved_user(TestRepo)
    {:ok, category} =
      @category_params
      |> Map.put(:creator_id, user.id)
      |> ImageCategory.create(user)
    {:ok, series} =
      @series_params
      |> Map.put(:creator_id, user.id)
      |> Map.put(:image_category_id, category.id)
      |> ImageSeries.create(user)
    {:ok, %{user: user, category: category, series: series}}
  end

  test "get_by_category_id", %{category: category} do
    result = ImageSeries.get_by_category_id(category.id)
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
