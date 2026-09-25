defmodule Brando.Videos.MetadataTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Videos
  alias Brando.Videos.Metadata

  @master """
  #EXTM3U
  #EXT-X-STREAM-INF:BANDWIDTH=1276000,RESOLUTION=640x360
  360p/video.m3u8
  #EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1920x1080
  1080p/video.m3u8
  """

  @playlist """
  #EXTM3U
  #EXTINF:4.000,
  a.ts
  #EXTINF:4.000,
  b.ts
  #EXTINF:3.500,
  c.ts
  """

  defp stub(routes) do
    test = self()

    Req.Test.stub(Metadata, fn conn ->
      send(test, {:request, conn.request_path, Plug.Conn.get_req_header(conn, "referer")})

      case routes.(conn.request_path, conn.query_string) do
        {:json, body} -> Req.Test.json(conn, body)
        {:jpeg, body} -> conn |> Plug.Conn.put_resp_content_type("image/jpeg") |> Plug.Conn.send_resp(200, body)
        {:text, body} -> Plug.Conn.send_resp(conn, 200, body)
        status -> Plug.Conn.send_resp(conn, status, "")
      end
    end)
  end

  test "reads the size and duration of a Bunny stream from its playlists" do
    assert Metadata.largest_rendition(@master) == {:ok, {1920, 1080, "1080p/video.m3u8"}}
    assert Metadata.playlist_duration(@playlist) == 11.5

    stub(fn
      "/guid/playlist.m3u8", _ -> {:text, @master}
      "/guid/1080p/video.m3u8", _ -> {:text, @playlist}
    end)

    video = %Videos.Video{type: :external_file, source_url: "https://vz-1.b-cdn.net/guid/playlist.m3u8"}

    assert {:ok, found} = Metadata.lookup(video)

    assert found == %{
             width: 1920,
             height: 1080,
             duration: 11.5,
             thumbnail_url: "https://vz-1.b-cdn.net/guid/thumbnail.jpg"
           }

    # Bunny pull zones only serve the site's own domain.
    assert_received {:request, "/guid/playlist.m3u8", [referer]}
    assert referer =~ Brando.Utils.hostname()
  end

  test "looks up a Vimeo file link through Vimeo's oEmbed, asking for a larger thumbnail" do
    stub(fn "/api/oembed.json", query ->
      assert URI.decode_query(query)["url"] == "https://vimeo.com/1216935742"

      {:json,
       %{
         "title" => "BY_case_OV",
         "duration" => 11,
         "thumbnail_url" => "https://i.vimeocdn.com/video/1-d_295x166?region=us"
       }}
    end)

    video = %Videos.Video{
      type: :external_file,
      source_url: "https://player.vimeo.com/progressive_redirect/playback/1216935742/rendition/720p/file.mp4?loc=external"
    }

    assert {:ok, %{title: "BY_case_OV", duration: 11, thumbnail_url: "https://i.vimeocdn.com/video/1-d_1280?region=us"}} =
             Metadata.lookup(video)

    download = %{
      video
      | source_url: "https://player.vimeo.com/progressive_redirect/download/1216935742/rendition/1080p/file.mp4"
    }

    assert {:ok, %{title: "BY_case_OV"}} = Metadata.lookup(download)
  end

  test "a title that is only the URL's file name is a placeholder" do
    url = "https://player.vimeo.com/playback/1/rendition/720p/file.mp4%20%28720p%29.mp4?loc=external"

    assert Videos.placeholder_title?(%Videos.Video{title: "file.mp4%20%28720p%29", source_url: url})
    assert Videos.placeholder_title?(%Videos.Video{title: nil, source_url: url})
    refute Videos.placeholder_title?(%Videos.Video{title: "Sommerro", source_url: url})
  end

  test "fills in what the video lacks, storing the thumbnail as an image, and keeps what it has" do
    user = Factory.insert(:random_user)
    jpeg = File.read!(Path.join([__DIR__, "..", "..", "fixtures", "sample.jpg"]))

    video =
      Factory.insert(:video,
        type: :vimeo,
        remote_id: "42",
        source_url: "https://vimeo.com/42",
        title: nil,
        width: 1280,
        height: 720,
        creator_id: user.id
      )

    stub(fn
      "/api/oembed.json", _ ->
        {:json, %{"title" => "Sommerro", "duration" => 65, "thumbnail_url" => "https://i.vimeocdn.com/video/9-d_295x166"}}

      "/video/9-d_1280", _ ->
        {:jpeg, jpeg}
    end)

    assert {:ok, video} = Videos.fetch_metadata(video, user)
    video = Brando.Repo.preload(video, :thumbnail)

    assert video.title == "Sommerro"
    assert video.duration == "00:01:05"
    assert {video.width, video.height} == {1280, 720}
    assert video.thumbnail.status == :processed
    assert video.thumbnail.path =~ "images/videos/thumbnails/"
  end

  test "a video added by URL is looked up in the background" do
    Application.put_env(:brando, Metadata, Keyword.put(Application.get_env(:brando, Metadata), :fetch_on_create, true))

    on_exit(fn ->
      Application.put_env(:brando, Metadata, Keyword.put(Application.get_env(:brando, Metadata), :fetch_on_create, false))
    end)

    user = Factory.insert(:random_user)
    stub(fn "/api/oembed.json", _ -> {:json, %{"title" => "Utklipp"}} end)

    {:ok, video} =
      Videos.create_video(
        %{type: :vimeo, remote_id: "7", source_url: "https://vimeo.com/7", config_target: "default"},
        user
      )

    # Oban runs inline in tests.
    assert Brando.Repo.get(Videos.Video, video.id).title == "Utklipp"
  end
end
