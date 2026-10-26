defmodule Brando.Videos.MetadataTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Videos
  alias Brando.Videos.Helpers
  alias Brando.Videos.Metadata
  alias Plug.Conn

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
      send(test, {:request, conn.request_path, Conn.get_req_header(conn, "referer")})

      case routes.(conn.request_path, conn.query_string) do
        {:json, body} -> Req.Test.json(conn, body)
        {:jpeg, body} -> conn |> Conn.put_resp_content_type("image/jpeg") |> Conn.send_resp(200, body)
        {:text, body} -> Conn.send_resp(conn, 200, body)
        status -> Conn.send_resp(conn, status, "")
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
    refute Videos.placeholder_title?(%Videos.Video{title: "Example Hotel", source_url: url})
  end

  test "looks up an unlisted Vimeo video through its hashed page URL" do
    stub(fn "/api/oembed.json", query ->
      assert URI.decode_query(query)["url"] == "https://vimeo.com/42/abcdef1234"
      {:json, %{"title" => "Unlisted"}}
    end)

    video = %Videos.Video{type: :vimeo, remote_id: "42", source_url: "https://vimeo.com/42/abcdef1234"}

    assert {:ok, %{title: "Unlisted"}} = Metadata.lookup(video)
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
        {:json,
         %{"title" => "Example Hotel", "duration" => 65, "thumbnail_url" => "https://i.vimeocdn.com/video/9-d_295x166"}}

      "/video/9-d_1280", _ ->
        {:jpeg, jpeg}
    end)

    assert {:ok, video} = Videos.fetch_metadata(video, user)
    video = Brando.Repo.preload(video, :thumbnail)

    assert video.title == "Example Hotel"
    assert video.duration == "00:01:05"
    assert {video.width, video.height} == {1280, 720}
    assert video.thumbnail.status == :processed
    assert video.thumbnail.path =~ "images/videos/thumbnails/"
  end

  # Asked for again while the first lookup still waits (the queue is busy,
  # or it is retrying), the video is looked up once.
  test "a lookup still waiting is not queued twice" do
    user = Factory.insert(:random_user)
    video = Factory.insert(:video, creator: user, type: :vimeo, remote_id: "8", source_url: "https://vimeo.com/8")

    Oban.Testing.with_testing_mode(:manual, fn ->
      Videos.enqueue_metadata([video.id], user)
      age_jobs(Brando.Worker.VideoMetadata, 600)
      Videos.enqueue_metadata([video.id], user)

      assert [_one] = all_enqueued(worker: Brando.Worker.VideoMetadata, args: %{"video_id" => video.id})
    end)
  end

  # A lookup waiting as a step of the same work counts itself when it ends
  test "a lookup already waiting for the same work is not counted twice" do
    user = Factory.insert(:random_user)
    video = Factory.insert(:video, creator: user, type: :vimeo, remote_id: "9", source_url: "https://vimeo.com/9")
    BrandoAdmin.Work.subscribe(user)
    BrandoAdmin.Work.start(user, "lookups", "Looking up", total: 2)

    Oban.Testing.with_testing_mode(:manual, fn ->
      Videos.enqueue_metadata([video.id], user, work: "lookups")
      age_jobs(Brando.Worker.VideoMetadata, 600)
      Videos.enqueue_metadata([video.id], user, work: "lookups")
    end)

    BrandoAdmin.Work.Registry.sync()
    assert %BrandoAdmin.Work{done: 0} = BrandoAdmin.Work.get(user, "lookups")

    # Waiting for other work, or none, it counts at once
    Oban.Testing.with_testing_mode(:manual, fn -> Videos.enqueue_metadata([video.id], user, work: "other") end)
    BrandoAdmin.Work.start(user, "other", "Looking up", total: 1)
    Oban.Testing.with_testing_mode(:manual, fn -> Videos.enqueue_metadata([video.id], user, work: "other") end)
    assert_receive {:work, "other", :finished, _}
    BrandoAdmin.Work.finish(user, "lookups")
  end

  defp age_jobs(worker, seconds) do
    import Ecto.Query, only: [from: 2]
    inserted_at = DateTime.add(DateTime.utc_now(), -seconds)
    Brando.Repo.update_all(from(j in Oban.Job, where: j.worker == ^inspect(worker)), set: [inserted_at: inserted_at])
  end

  # Audit F12: a provider is the parsed URL's host, and every request goes
  # through Brando.Webhooks.URLGuard to the address it checked, without
  # following redirects.
  describe "requests stay with the provider" do
    defp external(url), do: %Videos.Video{type: :external_file, source_url: url}

    test "a provider's host elsewhere in the URL is not the provider" do
      stub(fn _, _ -> {:text, @master} end)

      for url <- [
            "http://169.254.169.254/latest/.b-cdn.net/x/playlist.m3u8",
            "https://evil.example.com/.b-cdn.net/x/playlist.m3u8",
            "https://vz-1.b-cdn.net.evil.example.com/x/playlist.m3u8",
            "https://vz-1.b-cdn.net@evil.example.com/x/playlist.m3u8",
            "http://vz-1.b-cdn.net/x/playlist.m3u8",
            "https://vz-1.b-cdn.net:6379/x/playlist.m3u8",
            "https://vz-1.b-cdn.net/x/playlist.m3u8?token=abc",
            "https://vz-1.b-cdn.net/x?a=/playlist.m3u8",
            "https://evil.example.com/player.vimeo.com/external/42/file.mp4"
          ] do
        assert Metadata.lookup(external(url)) == {:error, :unsupported}, url
        assert Helpers.derive_external_thumbnail_url(external(url)) == nil, url
      end

      assert Helpers.derive_external_thumbnail_url(external("https://evil.example.com/https://stream.mux.com/abc")) == nil
      refute_received {:request, _, _}
    end

    test "the providers' own URLs still match" do
      assert Helpers.derive_external_thumbnail_url(external("https://VZ-1.B-CDN.NET/guid/playlist.m3u8")) ==
               "https://VZ-1.B-CDN.NET/guid/thumbnail.jpg"

      assert Metadata.lookup(external("https://stream.mux.com/abc123.m3u8")) ==
               {:ok, %{thumbnail_url: "https://image.mux.com/abc123/thumbnail.jpg"}}

      stub(fn "/api/oembed.json", _ -> {:json, %{"title" => "Clip"}} end)

      assert {:ok, %{title: "Clip"}} =
               Metadata.lookup(external("https://player.vimeo.com/external/42.hd.mp4?s=abc"))
    end

    test "a provider host resolving to a private address is not requested" do
      stub(fn _, _ -> {:text, @master} end)
      url = "https://private-zone.b-cdn.net/guid/playlist.m3u8"

      # Only the thumbnail's derived URL comes back, and fetching it is refused.
      assert {:ok, %{thumbnail_url: thumbnail}} = Metadata.lookup(external(url))
      assert Metadata.download(thumbnail) == {:error, :private_address}
      assert Metadata.download("https://10.0.0.5/thumbnail.jpg") == {:error, :private_address}
      assert Metadata.download("http://169.254.169.254/latest/meta-data") == {:error, :https_required}
      refute_received {:request, _, _}
    end

    test "a redirect is not followed" do
      test = self()

      Req.Test.stub(Metadata, fn conn ->
        send(test, {:request, conn.request_path, []})

        conn
        |> Conn.put_resp_header("location", "http://10.0.0.5/internal/playlist.m3u8")
        |> Conn.send_resp(302, "")
      end)

      assert {:ok, found} = Metadata.lookup(external("https://vz-1.b-cdn.net/guid/playlist.m3u8"))
      assert found == %{thumbnail_url: "https://vz-1.b-cdn.net/guid/thumbnail.jpg"}
      assert Metadata.download("https://vz-1.b-cdn.net/guid/thumbnail.jpg") == {:error, {:http, 302}}

      assert_received {:request, "/guid/playlist.m3u8", _}
      assert_received {:request, "/guid/thumbnail.jpg", _}
      refute_received {:request, "/internal/playlist.m3u8", _}
    end

    test "a redirect or a refused address is not looked up again" do
      user = Factory.insert(:random_user)
      video = Factory.insert(:video, creator: user, type: :vimeo, remote_id: "8", source_url: "https://vimeo.com/8")
      stub(fn _, _ -> 302 end)

      assert {:cancel, {:http, 302}} =
               perform_job(Brando.Worker.VideoMetadata, %{"video_id" => video.id, "user_id" => user.id})

      put_test_env(Brando.Webhooks, resolver: fn _host -> {:ok, [{10, 0, 0, 5}]} end)

      assert {:cancel, :private_address} =
               perform_job(Brando.Worker.VideoMetadata, %{"video_id" => video.id, "user_id" => user.id})
    end

    test "a rendition on another host is not read" do
      master = """
      #EXTM3U
      #EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1920x1080
      https://other.b-cdn.net/chosen/video.m3u8
      """

      stub(fn
        "/guid/playlist.m3u8", _ -> {:text, master}
        _, _ -> {:text, @playlist}
      end)

      assert {:ok, found} = Metadata.lookup(external("https://vz-1.b-cdn.net/guid/playlist.m3u8"))
      assert found == %{width: 1920, height: 1080, thumbnail_url: "https://vz-1.b-cdn.net/guid/thumbnail.jpg"}

      assert_received {:request, "/guid/playlist.m3u8", _}
      refute_received {:request, "/chosen/video.m3u8", _}
    end

    # Over a real socket: the stub is off and a listener waits on loopback.
    test "no request reaches a loopback listener, and one allowed is not redirected" do
      put_test_env(Metadata, Keyword.delete(Application.get_env(:brando, Metadata), :req_options))

      receiver =
        Brando.WebhookReceiver.start(fn
          %{path: "/thumb.jpg"} -> {302, [{"location", "/second.jpg"}], ""}
          _request -> {200, [{"content-type", "image/jpeg"}], "jpeg"}
        end)

      port = receiver.port

      assert Metadata.lookup(external("http://127.0.0.1:#{port}/x/.b-cdn.net/y/playlist.m3u8")) ==
               {:error, :unsupported}

      assert Metadata.download("http://pinned.test:#{port}/plain.jpg") == {:error, :https_required}
      refute_receive {:webhook_request, _}, 200

      # The development override lets it reach loopback: it connects to the
      # address checked, keeps the host name, and does not follow the 302.
      put_test_env(Brando.Webhooks, allow_localhost: true, resolver: {Brando.WebhookTestResolver, :resolve})

      assert Metadata.download("http://pinned.test:#{port}/plain.jpg") == {:ok, "jpeg", "image/jpeg"}
      assert_receive {:webhook_request, %{method: "GET", path: "/plain.jpg", headers: %{"host" => host}}}
      assert host == "pinned.test:#{port}"

      assert Metadata.download("http://pinned.test:#{port}/thumb.jpg") == {:error, {:http, 302}}
      assert_receive {:webhook_request, %{path: "/thumb.jpg"}}
      refute_receive {:webhook_request, %{path: "/second.jpg"}}, 200
    end

    test "an IPv6 address is connected to by address, and the host keeps its name" do
      put_test_env(Metadata, Keyword.delete(Application.get_env(:brando, Metadata), :req_options))
      put_test_env(Brando.Webhooks, allow_localhost: true, resolver: fn _host -> {:ok, [{0, 0, 0, 0, 0, 0, 0, 1}]} end)

      receiver =
        Brando.WebhookReceiver.start(fn _ -> {200, [{"content-type", "image/png"}], "png"} end, {0, 0, 0, 0, 0, 0, 0, 1})

      assert Metadata.download("http://pinned6.test:#{receiver.port}/a.png") == {:ok, "png", "image/png"}
      assert_receive {:webhook_request, %{path: "/a.png", headers: %{"host" => host}}}
      assert host == "pinned6.test:#{receiver.port}"
    end
  end

  describe "a video added by URL" do
    setup do
      Application.put_env(:brando, Metadata, Keyword.put(Application.get_env(:brando, Metadata), :fetch_on_create, true))

      on_exit(fn ->
        Application.put_env(
          :brando,
          Metadata,
          Keyword.put(Application.get_env(:brando, Metadata), :fetch_on_create, false)
        )
      end)

      stub(fn "/api/oembed.json", _ -> {:json, %{"title" => "Utklipp"}} end)
      %{user: Factory.insert(:random_user)}
    end

    test "is looked up in the background", %{user: user} do
      {:ok, video} =
        Videos.create_video(
          %{type: :vimeo, remote_id: "7", source_url: "https://vimeo.com/7", config_target: "default"},
          user
        )

      # Oban runs inline in tests.
      assert Brando.Repo.get(Videos.Video, video.id).title == "Utklipp"
    end

    # The block editor and the URL handler pass the user's id.
    test "is looked up when created with a user id", %{user: user} do
      {:ok, video} =
        Videos.create_video(
          %{type: :vimeo, remote_id: "7", source_url: "https://vimeo.com/7", config_target: "default"},
          user.id
        )

      assert Brando.Repo.get(Videos.Video, video.id).title == "Utklipp"
    end
  end
end
