defmodule Brando.Integration.ImageCategoryTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  
  alias Brando.ImageCategory
  alias Brando.Factory

  setup do
    user = Factory.create(:user)
    category = Factory.create(:image_category, creator: user)
    series = Factory.create(:image_series, creator: user, image_category: category)
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
