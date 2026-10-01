defmodule Brando.Videos.ProviderLibraryTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Brando.Test.Support, only: [put_test_env: 2]
  import Plug.Conn

  alias Brando.Factory
  alias Brando.Videos.ProviderLibrary
  alias Brando.Videos.Uploader
  alias Brando.Videos.Uploaders.Bunny
  alias Brando.Videos.Uploaders.Cloudflare
  alias Brando.Videos.Uploaders.Mux
  alias Brando.Videos.Uploaders.Vimeo

  setup do
    put_test_env(Mux, [])
    put_test_env(Bunny, [])
    put_test_env(Cloudflare, [])
    put_test_env(Vimeo, access_token: "vimeo-token", req_options: [plug: {Req.Test, Vimeo}])
    {:ok, user: Factory.insert(:random_user)}
  end

  test "offers only configured providers" do
    assert ProviderLibrary.providers() == [%{strategy: :vimeo, label: "Vimeo", search?: true}]

    put_test_env(Mux, access_token_id: "id", access_token_secret: "secret")

    assert [%{strategy: :mux, search?: false}, %{strategy: :vimeo}] = ProviderLibrary.providers()
    assert {:error, {:unknown_strategy, :bunny}} = ProviderLibrary.list(:bunny)
  end

  test "lists a page, marking what is already in the library", %{user: user} do
    existing =
      Factory.insert(:video,
        creator: user,
        type: :vimeo_account,
        meta: %{"provider" => "vimeo", "vimeo" => %{"video_id" => "2"}}
      )

    Req.Test.expect(Vimeo, fn conn ->
      assert conn.request_path == "/me/videos"
      assert %{"page" => "1", "per_page" => "24", "query" => "summer", "sort" => "date"} = conn.query_params

      Req.Test.json(conn, %{
        "paging" => %{"next" => "/me/videos?page=2"},
        "data" => [vimeo_video("1", "available"), vimeo_video("2", "available"), vimeo_video("3", "transcoding")]
      })
    end)

    assert {:ok, %{items: [one, two, three], next: 2}} = ProviderLibrary.list(:vimeo, query: "summer")

    assert %{remote_id: "1", title: "Video 1", status: :ready, playable?: true, video_id: nil} = one
    assert one.thumbnail_url == "https://i.vimeocdn.com/video/1-d_1280"
    assert {one.width, one.height, one.duration} == {1280, 720, 30}
    assert two.video_id == existing.id
    assert %{status: :processing, playable?: false} = three
  end

  test "imports a remote video once, and never deletes it remotely", %{user: user} do
    Req.Test.expect(Vimeo, fn conn ->
      assert conn.request_path == "/videos/42"
      Req.Test.json(conn, vimeo_video("42", "available"))
    end)

    assert {:ok, video} = ProviderLibrary.import(:vimeo, "42", user, config_target: "default")

    assert video.type == :vimeo_account
    assert video.status == :ready
    assert video.title == "Video 42"
    assert video.config_target == "default"
    assert video.meta["imported"] == true
    assert ProviderLibrary.imported?(video)
    assert Vimeo.get_playback_url(video) == {:ok, "https://player.vimeo.com/external/42.m3u8?s=x"}

    # A second add finds the record rather than asking Vimeo again.
    assert {:ok, again} = ProviderLibrary.import(:vimeo, "42", user)
    assert again.id == video.id

    put_test_env(Vimeo, access_token: "vimeo-token", delete_remote_on: :on_delete, req_options: [plug: {Req.Test, Vimeo}])

    assert Uploader.get_delete_timing(video) == false
    # No stub is set: a request would fail the test.
    assert :ok = Uploader.delete_remote(video)
  end

  test "a provider error comes back as an error tuple", %{user: user} do
    Req.Test.expect(Vimeo, &send_resp(&1, 403, "forbidden"))
    assert {:error, {:http_error, 403, _}} = ProviderLibrary.list(:vimeo)

    Req.Test.expect(Vimeo, &send_resp(&1, 404, ""))
    assert {:error, :not_found} = ProviderLibrary.import(:vimeo, "7", user)
  end

  describe "other providers" do
    test "Cloudflare pages by creation date and refuses signed videos", %{user: user} do
      put_test_env(Cloudflare,
        account_id: "acc",
        api_token: "token",
        webhook_secret: "secret",
        req_options: [plug: {Req.Test, Cloudflare}]
      )

      Req.Test.expect(Cloudflare, fn conn ->
        assert conn.request_path == "/client/v4/accounts/acc/stream"
        assert conn.query_params == %{"limit" => "2", "before" => "2026-09-01T00:00:00Z"}

        Req.Test.json(conn, %{
          "result" => [cloudflare_video("a", "2026-08-02T00:00:00Z"), cloudflare_video("b", "2026-08-01T00:00:00Z")]
        })
      end)

      assert {:ok, %{items: [%{remote_id: "a", playable?: true}, _], next: "2026-08-01T00:00:00Z"}} =
               ProviderLibrary.list(:cloudflare, per_page: 2, cursor: "2026-09-01T00:00:00Z")

      Req.Test.expect(Cloudflare, fn conn ->
        Req.Test.json(conn, %{"result" => Map.put(cloudflare_video("s", nil), "requireSignedURLs", true)})
      end)

      assert {:error, :signed_playback_not_supported} = ProviderLibrary.import(:cloudflare, "s", user)

      Req.Test.expect(Cloudflare, &Req.Test.json(&1, %{"result" => cloudflare_video("a", nil)}))

      assert {:ok, %{type: :cloudflare, status: :ready, meta: %{"imported" => true}}} =
               ProviderLibrary.import(:cloudflare, "a", user)
    end

    test "Mux lists assets and imports one with public playback", %{user: user} do
      put_test_env(Mux, access_token_id: "id", access_token_secret: "secret", req_options: [plug: {Req.Test, Mux}])

      asset = %{
        "id" => "asset-1",
        "status" => "ready",
        "duration" => 12.5,
        "aspect_ratio" => "16:9",
        "created_at" => "1767225600",
        "passthrough" => "Launch film",
        "playback_ids" => [%{"id" => "pb-1", "policy" => "public"}],
        "tracks" => [%{"type" => "video", "max_width" => 1920, "max_height" => 1080}]
      }

      Req.Test.expect(Mux, fn conn ->
        assert conn.request_path == "/video/v1/assets"
        assert conn.query_params == %{"limit" => "24", "page" => "1"}
        Req.Test.json(conn, %{"data" => [asset]})
      end)

      assert {:ok, %{items: [item], next: nil}} = ProviderLibrary.list(:mux)
      assert %{remote_id: "asset-1", title: "Launch film", width: 1920, playable?: true} = item
      assert item.created_at == "2026-01-01T00:00:00Z"

      Req.Test.expect(Mux, &Req.Test.json(&1, %{"data" => asset}))

      assert {:ok, video} = ProviderLibrary.import(:mux, "asset-1", user)
      assert {video.type, video.status, video.title} == {:mux, :ready, "Launch film"}
      assert get_in(video.meta, ["mux", "playback_id"]) == "pb-1"
    end

    test "Bunny lists a library page and imports a finished video", %{user: user} do
      put_test_env(Bunny,
        api_key: "key",
        library_id: "77",
        cdn_hostname: "vz-1.b-cdn.net",
        req_options: [plug: {Req.Test, Bunny}]
      )

      bunny_video = %{
        "guid" => "6f2c1a3e-1111-2222-3333-444455556666",
        "videoLibraryId" => 77,
        "title" => "Harbour",
        "status" => 4,
        "length" => 20,
        "width" => 1280,
        "height" => 720,
        "thumbnailFileName" => "thumbnail.jpg"
      }

      Req.Test.expect(Bunny, fn conn ->
        assert conn.request_path == "/library/77/videos"
        assert %{"page" => "1", "orderBy" => "date"} = conn.query_params
        Req.Test.json(conn, %{"items" => [bunny_video], "currentPage" => 1, "itemsPerPage" => 24, "totalItems" => 30})
      end)

      assert {:ok, %{items: [item], next: 2}} = ProviderLibrary.list(:bunny)
      assert item.thumbnail_url == "https://vz-1.b-cdn.net/6f2c1a3e-1111-2222-3333-444455556666/thumbnail.jpg"

      Req.Test.expect(Bunny, &Req.Test.json(&1, bunny_video))

      assert {:ok, video} = ProviderLibrary.import(:bunny, bunny_video["guid"], user)
      assert {video.type, video.status, video.width} == {:bunny, :ready, 1280}
    end
  end

  defp vimeo_video(id, status) do
    %{
      "uri" => "/videos/#{id}",
      "name" => "Video #{id}",
      "link" => "https://vimeo.com/#{id}",
      "player_embed_url" => "https://player.vimeo.com/video/#{id}",
      "status" => status,
      "transcode" => %{"status" => if(status == "available", do: "complete", else: "in_progress")},
      "width" => 1280,
      "height" => 720,
      "duration" => 30,
      "created_time" => "2026-09-01T10:00:00+00:00",
      "pictures" => %{"sizes" => [%{"width" => 1280, "link" => "https://i.vimeocdn.com/video/#{id}-d_1280"}]},
      "files" => [%{"quality" => "hls", "link" => "https://player.vimeo.com/external/#{id}.m3u8?s=x"}]
    }
  end

  defp cloudflare_video(uid, created) do
    %{
      "uid" => uid,
      "created" => created,
      "meta" => %{"name" => "Clip #{uid}"},
      "readyToStream" => true,
      "status" => %{"state" => "ready"},
      "duration" => 9.0,
      "input" => %{"width" => 1920, "height" => 1080},
      "thumbnail" => "https://customer.example.com/#{uid}/thumbnails/thumbnail.jpg",
      "playback" => %{"hls" => "https://customer.example.com/#{uid}/manifest/video.m3u8"}
    }
  end
end
