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
    img = Factory.insert(:image, creator_id: user.id)

    # A plain string lands under the default language.
    assert {:ok, img} = Images.update_image(img, %{title: "Hey"}, user)
    assert img.title == %{"en" => "Hey"}

    assert {:ok, img} = Images.update_image(img, %{title: %{"en" => "Hey", "no" => "Hei"}}, user)
    assert Images.text(img, :title, "no") == "Hei"
  end

  describe "text/3" do
    test "reads the language asked for, else the default language" do
      image = %Brando.Images.Image{alt: %{"en" => "A ferry", "no" => "En ferje", "de" => "  "}}

      assert Images.text(image, :alt, "no") == "En ferje"
      assert Images.text(image, :alt, :no) == "En ferje"
      # Blank counts as missing.
      assert Images.text(image, :alt, "de") == "A ferry"
      assert Images.text(image, :alt, "fr") == "A ferry"
      assert Images.text(image, :alt, nil) == "A ferry"
      assert Images.text(%Brando.Images.Image{alt: nil}, :alt, "no") == nil
      assert Images.text(nil, :alt, "no") == nil
    end

    test "passes a placement's plain string through" do
      assert Images.text(%{alt: "Override"}, :alt, "no") == "Override"
    end
  end

  test "resolve_texts/2 turns an image's maps into text, leaving strings alone" do
    image = %Brando.Images.Image{alt: %{"no" => "En ferje", "en" => "A ferry"}, title: "Placement title", credits: nil}
    resolved = Images.resolve_texts(image, "no")

    assert resolved.alt == "En ferje"
    assert resolved.title == "Placement title"
    assert resolved.credits == nil
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
