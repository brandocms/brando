defmodule Brando.Videos.PlaybackTest do
  use ExUnit.Case, async: false

  import Brando.Test.Support, only: [put_test_env: 2]

  alias Brando.Videos.Playback
  alias Brando.Videos.Video

  @guid "6f2c1a3e-1111-2222-3333-444455556666"

  setup do
    put_test_env(Brando.Videos.Uploaders.Bunny, cdn_hostname: "vz-1.b-cdn.net")
    put_test_env(Brando.Videos, [])
    :ok
  end

  defp bunny(bunny_meta \\ %{"has_mp4_fallback" => true, "available_resolutions" => "240p,360p,480p,720p"}, attrs \\ %{}) do
    struct(%Video{type: :bunny, status: :ready, meta: %{"bunny" => Map.put(bunny_meta, "video_guid", @guid)}}, attrs)
  end

  defp url(file), do: "https://vz-1.b-cdn.net/#{@guid}/#{file}"

  test "the Video schema and the block data take every quality" do
    assert Ecto.Enum.values(Video, :quality) == Playback.qualities()
    assert Ecto.Enum.values(Brando.Villain.Blocks.VideoBlock.Data, :quality) == Playback.qualities()
    assert Ecto.Enum.values(Brando.Villain.Blocks.GalleryObjectOverride, :quality) == Playback.qualities()
  end

  # What the drawer's select and a block's send: "" for the inherited value
  test "a video and a block cast the select's value, and an empty one to nil" do
    user = %Brando.Users.User{id: 1}

    assert Video.changeset(%Video{quality: :hls}, %{"quality" => "mp4_720"}, user).changes.quality == :mp4_720
    assert Video.changeset(%Video{quality: :hls}, %{"quality" => ""}, user).changes.quality == nil

    data = Ecto.Changeset.cast(%Brando.Villain.Blocks.VideoBlock.Data{}, %{"quality" => "hls"}, [:quality])
    assert data.changes.quality == :hls
  end

  test "normalize/1 reads atoms and the strings forms and configs hold" do
    assert Playback.normalize(:mp4_720) == :mp4_720
    assert Playback.normalize("mp4_720") == :mp4_720
    assert Playback.normalize("hls") == :hls
    assert Playback.normalize("") == nil
    assert Playback.normalize("mp4_9999") == nil
    assert Playback.normalize(nil) == nil
  end

  test "a Bunny video with MP4 Fallback offers the MP4s it has" do
    assert Playback.mp4_resolutions(bunny()) == [360, 480, 720]
    assert Playback.choices(bunny()) == [:auto, :hls, :mp4_360, :mp4_480, :mp4_720]
  end

  # Only `true` offers MP4s: a video stored before Brando kept the flag may be
  # in a library without MP4 Fallback, whose play_*p.mp4 are 404s
  test "a Bunny video without MP4 Fallback, or not known to have it, offers the stream only" do
    for meta <- [
          %{"has_mp4_fallback" => false, "available_resolutions" => "360p,720p"},
          %{"available_resolutions" => "720p"}
        ] do
      assert Playback.mp4_resolutions(bunny(meta)) == []
      assert Playback.choices(bunny(meta)) == [:auto, :hls]
      assert Playback.source(bunny(meta, %{quality: :mp4_720}), []) == {:hls, url("playlist.m3u8")}
      assert Playback.source(bunny(meta), []) == {:hls, url("playlist.m3u8")}
    end
  end

  test "videos without renditions to choose from offer nothing" do
    for type <- [:upload, :external_file, :youtube, :vimeo] do
      assert Playback.choices(%Video{type: type}) == []
    end

    assert Playback.choices(nil) == []
  end

  test "a fixed MP4 plays that resolution" do
    assert Playback.source(
             bunny(%{"has_mp4_fallback" => true, "available_resolutions" => "360p,720p"}, %{quality: :mp4_720}),
             []
           ) ==
             {:mp4, url("play_720p.mp4")}
  end

  test "a resolution the video lacks falls back to the next one down, or the lowest" do
    video = bunny(%{"has_mp4_fallback" => true, "available_resolutions" => "480p,720p"})

    assert Playback.source(%{video | quality: :mp4_1080}, []) == {:mp4, url("play_720p.mp4")}
    assert Playback.source(%{video | quality: :mp4_360}, []) == {:mp4, url("play_480p.mp4")}
  end

  test "streaming plays the playlist" do
    assert Playback.source(bunny(%{"has_mp4_fallback" => true, "available_resolutions" => "720p"}, %{quality: :hls}), []) ==
             {:hls, url("playlist.m3u8")}
  end

  test "automatic plays a loop as the default MP4, and streams a video someone may watch through" do
    video = bunny()

    assert Playback.source(video, []) == {:mp4, url("play_720p.mp4")}
    assert Playback.source(video, controls: true) == {:hls, url("playlist.m3u8")}
    assert Playback.source(video, play_button: "Play") == {:hls, url("playlist.m3u8")}
  end

  test "the site default sets the resolution automatic plays" do
    put_test_env(Brando.Videos, default_mp4_resolution: 480)
    assert Playback.source(bunny(), []) == {:mp4, url("play_480p.mp4")}
  end

  test "the record's quality beats the template's, and nil inherits it" do
    video = bunny()

    assert Playback.source(%{video | quality: :hls}, quality: :mp4_360) == {:hls, url("playlist.m3u8")}
    assert Playback.source(video, quality: :mp4_360) == {:mp4, url("play_360p.mp4")}
    assert Playback.source(video, quality: "hls") == {:hls, url("playlist.m3u8")}
  end
end
