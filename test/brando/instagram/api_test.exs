defmodule Brando.Instagram.APITest do
  use ExUnit.Case, async: false
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney
  alias Brando.Instagram.API
  alias Brando.InstagramImage

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
    use_cassette "instagram_get_user_images", custom: true do
      assert API.images_for_user("dummy_user", min_timestamp: "1412585305") == :ok
      assert length(InstagramImage.all) > 0
    end
  end

  test "get images for tags" do
    use_cassette "instagram_get_tag_images", custom: true do
      assert API.images_for_tags(["haraball"], min_id: "968134024444958851") == :ok
      assert length(InstagramImage.all) > 0
    end
  end
end