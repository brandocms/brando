defmodule Brando.Integration.ImageCategoryTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  alias Brando.ImageSeries
  alias Brando.ImageCategory
  alias Brando.Type.ImageConfig

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

  test "get_slug", %{category: category} do
    assert ImageCategory.get_slug(id: category.id) == "test-category"
  end

  test "meta", %{category: category} do
    assert ImageCategory.__name__(:singular) == "image category"
    assert ImageCategory.__name__(:plural) == "image categories"
    assert ImageCategory.__repr__(category) == "Test Category"
  end
end
