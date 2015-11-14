defmodule Brando.Instagram.APITest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  alias Brando.Instagram.API
  alias Brando.InstagramImage

  @instaimage %{
    "approved" => true,
    "caption" => "",
    "created_time" => "1412585304",
    "deleted" => false,
    "id" => 3261,
    "instagram_id" => "968134024444958851_000000",
    "username" => "username",
    "link" => "https://instagram.com/p/fakelink/",
    "type" => "image",
    "url_original" => "https://scontent.cdninstagram.com/" <>
                      "hphotos-xft1/t51.2885-15/e15/0.jpg",
    "url_thumbnail" => "https://scontent.cdninstagram.com/" <>
                       "hphotos-xft1/t51.2885-15/s150x150/e15/0.jpg"}

  test "get_user_id" do
    assert API.get_user_id("dummy_user") == {:ok, "0123456"}
  end

  test "get images for user" do
    Brando.repo.delete_all(InstagramImage)
    assert API.images_for_user("dummy_user", min_timestamp: "1412585305")
           == :ok
    assert length(Brando.repo.all(InstagramImage)) == 2
    Brando.repo.delete_all(InstagramImage)
    assert API.images_for_user("dummy_user", max_id: "968134024444958851")
           == :ok
    assert length(Brando.repo.all(InstagramImage)) == 2
  end

  test "get images for tags" do
    Brando.repo.delete_all(InstagramImage)
      assert API.images_for_tags(["haraball"], min_id: "968134024444958851")
             == :ok
      assert length(Brando.repo.all(InstagramImage)) == 1
  end

  test "fetch user" do
    # dump images
    Brando.repo.delete_all(InstagramImage)
    cfg = Application.get_env(:brando, Brando.Instagram)
    cfg = Keyword.put(cfg, :fetch, {:user, "dummy_user"})
    Application.put_env(:brando, Brando.Instagram, cfg)
    # install fake image in db
    {:ok, _} = InstagramImage.create(@instaimage)

    assert API.fetch(:blank, cfg[:fetch]) == {:ok, "1429882831"}
    assert API.fetch("1412585305", cfg[:fetch]) == {:ok, "1429882831"}
  end

  test "fetch tag" do
    # dump images
    Brando.repo.delete_all(InstagramImage)
    cfg = Application.get_env(:brando, Brando.Instagram)
    cfg = Keyword.put(cfg, :fetch, {:tags, ["haraball"]})
    Application.put_env(:brando, Brando.Instagram, cfg)
    # install fake image in db
    {:ok, _} = InstagramImage.create(@instaimage)
    assert API.fetch(:blank, cfg[:fetch])
           == {:ok, "970249962242331087"}
    assert API.fetch("968134024444958851", cfg[:fetch])
           == {:ok, "970249962242331087"}
  end

  test "client_id error" do
    assert API.get_user_id("asf98293h8a9283fh9a238fh")
           == {:error, "Instagram API 400 error: \"The client_id " <>
                       "provided is invalid and does not match a valid " <>
                       "application.\""}
  end

  test "user not found" do
    assert API.get_user_id("djasf98293h8a9283fh9a238fh")
           == {:error, "User not found: djasf98293h8a9283fh9a238fh"}
  end
end
