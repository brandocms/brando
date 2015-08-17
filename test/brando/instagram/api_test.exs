defmodule Brando.Instagram.APITest do
  use ExUnit.Case, async: false
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney
  use Brando.ConnCase
  alias Brando.Instagram.API
  alias Brando.InstagramImage

  @instaimage %{"approved" => true, "caption" => "", "created_time" => "1412585304",
                "deleted" => false, "id" => 3261, "instagram_id" => "968134024444958851_000000",
                "username" => "username", "link" => "https://instagram.com/p/fakelink/", "type" => "image",
                "url_original" => "https://scontent.cdninstagram.com/hphotos-xft1/t51.2885-15/e15/0.jpg",
                "url_thumbnail" => "https://scontent.cdninstagram.com/hphotos-xft1/t51.2885-15/s150x150/e15/0.jpg"}

  @rec_dir "../../test/fixtures/rec_cassettes"
  @dir "../../test/fixtures/cassettes"

  setup_all do
    HTTPoison.start
    ExVCR.Config.cassette_library_dir(@rec_dir, @dir)
  end

  test "get_user_id" do
    use_cassette "instagram_get_user_id", custom: true do
      assert API.get_user_id("dummy_user") == {:ok, "012345"}
    end
  end

  test "get images for user" do
    Brando.repo.delete_all(InstagramImage)
    use_cassette "instagram_get_user_images", custom: true do
      assert API.images_for_user("dummy_user", min_timestamp: "1412585305") == :ok
      assert length(InstagramImage |> Brando.repo.all) == 2
    end
    Brando.repo.delete_all(InstagramImage)
    use_cassette "instagram_get_user_images", custom: true do
      assert API.images_for_user("dummy_user", max_id: "968134024444958851") == :ok
      assert length(InstagramImage |> Brando.repo.all) == 2
    end

  end

  test "get images for tags" do
    Brando.repo.delete_all(InstagramImage)
    use_cassette "instagram_get_tag_images", custom: true do
      assert API.images_for_tags(["haraball"], min_id: "968134024444958851") == :ok
      assert length(InstagramImage |> Brando.repo.all) == 1
    end
  end

  test "fetch user" do
    # dump images
    Brando.repo.delete_all(InstagramImage)
    cfg = Application.get_env(:brando, Brando.Instagram)
    |> Keyword.put(:fetch, {:user, "dummy_user"})
    Application.put_env(:brando, Brando.Instagram, cfg)
    # install fake image in db
    {:ok, _} = InstagramImage.create(@instaimage)
    use_cassette "instagram_get_user_images", custom: true do
      assert API.fetch(:blank) == {:ok, "1429882831"}
      assert API.fetch("1412585305") == {:ok, "1429882831"}
    end
  end

  test "fetch tag" do
    # dump images
    Brando.repo.delete_all(InstagramImage)
    cfg = Application.get_env(:brando, Brando.Instagram)
    |> Keyword.put(:fetch, {:tags, ["haraball"]})
    Application.put_env(:brando, Brando.Instagram, cfg)
    # install fake image in db
    {:ok, _} = InstagramImage.create(@instaimage)
    use_cassette "instagram_get_tag_images", custom: true do
      assert API.fetch(:blank) == {:ok, "970249962242331087"}
      assert API.fetch("968134024444958851") == {:ok, "970249962242331087"}
    end
  end

  test "client_id error" do
    use_cassette "instagram_error_client_id", custom: true do
      assert API.get_user_id("asf98293h8a9283fh9a238fh") == {:error, "API feil 400 fra Instagram: \"The client_id provided is invalid and does not match a valid application.\""}
    end
  end

  test "user not found" do
    use_cassette "instagram_error_user_not_found", custom: true do
      assert API.get_user_id("djasf98293h8a9283fh9a238fh") == {:error, "Fant ikke bruker: djasf98293h8a9283fh9a238fh"}
    end
  end
end