defmodule Brando.ImagesTest do
  use ExUnit.Case
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Images

  test "create_image" do
    user = Factory.insert(:random_user)
    assert {:ok, _} = Images.create_image(Factory.params_for(:image), user)
  end

  test "update_image" do
    user = Factory.insert(:random_user)
    img = Factory.insert(:image)
    assert {:ok, img} = Images.update_image(img, %{sequence: 99}, user)
    assert img.sequence == 99
  end

  test "get_image" do
    img = Factory.insert(:image)
    {:ok, img2} = Images.get_image(%{matches: [id: img.id]})
    assert img == img2
  end

  test "get_image!" do
    img = Factory.insert(:image)
    assert img2 = Images.get_image!(img.id)
    assert img == img2
  end

  test "delete_images" do
    i1 = Factory.insert(:image)
    i2 = Factory.insert(:image)

    assert {2, nil} = Images.delete_images([i1.id, i2.id])
  end
end
