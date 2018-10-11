defmodule Brando.Integration.ImageCategoryTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase

  alias Brando.ImageCategory
  alias Brando.Factory

  setup do
    user = Factory.insert(:user)
    category = Factory.insert(:image_category, creator: user)
    series = Factory.insert(:image_series, creator: user, image_category: category)
    {:ok, %{user: user, category: category, series: series}}
  end

  test "meta", %{category: category} do
    assert ImageCategory.__name__(:singular) == "image category"
    assert ImageCategory.__name__(:plural) == "image categories"
    assert ImageCategory.__repr__(category) == "Test Category"
  end
end
