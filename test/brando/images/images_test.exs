defmodule Brando.ImagesTest do
  use ExUnit.Case
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Images

  test "create_image" do
    assert {:ok, _} = Images.create_image(Factory.params_for(:image), :system)
  end

  test "update_image" do
    img = Factory.insert(:image)
    assert {:ok, img} = Images.update_image(img, %{sequence: 99})
    assert img.sequence == 99
  end

  test "get_image!" do
    img = Factory.insert(:image)
    assert img2 = Images.get_image!(img.id)
    assert img == img2
  end

  test "update_image_meta" do
    img = Factory.insert(:image, image_series: Factory.build(:image_series))
    fixture = Path.join([Path.expand("../../", __DIR__), "fixtures", "sample.jpg"])
    target = Path.join([Images.Utils.media_path(img.image.path)])
    File.mkdir_p!(Path.dirname(target))

    File.cp_r!(
      fixture,
      target
    )

    assert {:ok, img2} = Images.update_image_meta(img, %{focal: %{x: 0, y: 0}}, :system)
    assert img2.image.focal == %{x: 0, y: 0}

    assert {:ok, img3} = Images.update_image_meta(img, %{title: "Hello!"}, :system)
    assert img3.image.title == "Hello!"
  end
end
