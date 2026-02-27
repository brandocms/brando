defmodule Brando.Videos.HelpersTest do
  use ExUnit.Case, async: true
  alias Brando.Videos.Helpers
  alias Brando.Videos.Video

  test "get_playback_url for :external_file with source_url" do
    assert {:ok, "https://example.com/video.mp4"} =
             Helpers.get_playback_url(%Video{
               type: :external_file,
               source_url: "https://example.com/video.mp4"
             })
  end

  test "get_playback_url for :external_file without source_url" do
    assert {:error, :missing_source_url} =
             Helpers.get_playback_url(%Video{type: :external_file, source_url: nil})
  end

  test "get_playback_url for :upload without file falls back to remote_id" do
    video = %Video{type: :upload, remote_id: "videos/default/test.mp4"}

    assert {:ok, url} = Helpers.get_playback_url(video)
    assert url =~ "videos/default/test.mp4"
  end

  test "get_playback_url for :upload without file or remote_id" do
    assert {:error, :file_not_loaded} =
             Helpers.get_playback_url(%Video{type: :upload, file: nil, remote_id: nil})
  end

  test "get_playback_url for unsupported type" do
    assert {:error, :unsupported_type} =
             Helpers.get_playback_url(%Video{type: :unknown})
  end
end
