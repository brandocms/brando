defmodule Brando.Videos.HelpersTest do
  use ExUnit.Case, async: true
  alias Brando.Videos.Helpers
  alias Brando.Videos.Video

  defp video(attrs), do: struct!(Video, attrs)

  test "get_playback_url for :external_file with source_url" do
    assert {:ok, "https://example.com/video.mp4"} =
             Helpers.get_playback_url(
               video(type: :external_file, source_url: "https://example.com/video.mp4")
             )
  end

  test "get_playback_url for :external_file without source_url" do
    assert {:error, :missing_source_url} =
             Helpers.get_playback_url(video(type: :external_file, source_url: nil))
  end

  test "get_playback_url for :upload without file falls back to remote_id" do
    assert {:ok, url} =
             Helpers.get_playback_url(video(type: :upload, remote_id: "videos/default/test.mp4"))

    assert url =~ "videos/default/test.mp4"
  end

  test "get_playback_url for :upload without file or remote_id" do
    assert {:error, :file_not_loaded} =
             Helpers.get_playback_url(video(type: :upload, file: nil, remote_id: nil))
  end

  test "get_playback_url for unsupported type" do
    assert {:error, :unsupported_type} =
             Helpers.get_playback_url(video(type: :unknown))
  end

  describe "thumbnail_url/1" do
    test "returns media URL for video with Image thumbnail" do
      result =
        Helpers.thumbnail_url(
          video(
            type: :upload,
            thumbnail: %Brando.Images.Image{path: "images/videos/thumbnails/thumb.jpg"}
          )
        )

      assert result =~ "images/videos/thumbnails/thumb.jpg"
    end

    test "returns Mux thumbnail URL for Mux video with playback_id" do
      result =
        Helpers.thumbnail_url(
          video(type: :mux, meta: %{"mux" => %{"playback_id" => "abc123"}})
        )

      assert result == "https://image.mux.com/abc123/thumbnail.jpg"
    end

    test "returns nil for Mux video without playback_id" do
      assert Helpers.thumbnail_url(video(type: :mux, meta: %{"mux" => %{}})) == nil
    end

    test "returns nil for YouTube video" do
      assert Helpers.thumbnail_url(video(type: :youtube)) == nil
    end

    test "returns nil for Vimeo video" do
      assert Helpers.thumbnail_url(video(type: :vimeo)) == nil
    end

    test "returns nil for upload video without thumbnail" do
      assert Helpers.thumbnail_url(video(type: :upload, thumbnail: nil)) == nil
    end
  end
end
