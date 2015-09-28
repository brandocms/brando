defmodule Brando.Integration.InstagramImageTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  alias Brando.InstagramImage

  @params %{"approved" => true, "caption" => "Image caption",
            "created_time" => "1412469138", "deleted" => false,
            "instagram_id" => "000000000000000000_000000",
            "link" => "https://instagram.com/p/dummy_link/", "type" => "image",
            "url_original" => "https://scontent.cdninstagram.com/0.jpg",
            "url_thumbnail" => "https://scontent.cdninstagram.com/0.jpg",
            "username" => "dummyuser"}

  test "create/1 and update/1" do
    assert {:ok, img}
           = InstagramImage.create(@params)
    assert {:ok, updated_img}
           = InstagramImage.update(img, %{"caption" => "New caption"})
    assert updated_img.caption
           == "New caption"
  end

  test "create/1 errors" do
    {_v, params} = Dict.pop @params, "caption"
    assert {:error, changeset} = InstagramImage.create(params)
    assert changeset.errors == [caption: "can't be blank"]
  end

  test "get/1" do
    assert {:ok, img} = InstagramImage.create(@params)
    assert Brando.repo.get_by!(InstagramImage, id: img.id) == img
  end

  test "delete/1" do
    assert {:ok, img} = InstagramImage.create(@params)
    InstagramImage.delete(img)
    assert Brando.repo.get_by(InstagramImage, id: img.id) == nil

    assert {:ok, img} = InstagramImage.create(@params)
    InstagramImage.delete(img.id)
    assert Brando.repo.get_by(InstagramImage, id: img.id) == nil
  end
end
