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
    assert ProviderLibrary.providers() == [%{strategy: :vimeo, label: "Vimeo", search?: true, collections?: true}]

    put_test_env(Mux, access_token_id: "id", access_token_secret: "secret")

    assert [%{strategy: :mux, search?: false, collections?: false}, %{strategy: :vimeo}] = ProviderLibrary.providers()
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

      # Asked once for the upload the asset came from, which may be the
      # library's already, and once to add it.
      Req.Test.expect(Mux, 2, &Req.Test.json(&1, %{"data" => asset}))

      assert {:ok, video} = ProviderLibrary.import(:mux, "asset-1", user)
      assert {video.type, video.status, video.title} == {:mux, :ready, "Launch film"}
      assert get_in(video.meta, ["mux", "playback_id"]) == "pb-1"
    end

    test "refuse a video the provider reports under another id", %{user: user} do
      Req.Test.expect(Vimeo, fn conn ->
        assert conn.request_path == "/videos/0042"
        Req.Test.json(conn, vimeo_video("42", "available"))
      end)

      assert {:error, :not_found} = ProviderLibrary.import(:vimeo, "0042", user)

      put_test_env(Cloudflare,
        account_id: "acc",
        api_token: "token",
        webhook_secret: "secret",
        req_options: [plug: {Req.Test, Cloudflare}]
      )

      Req.Test.expect(Cloudflare, &Req.Test.json(&1, %{"result" => cloudflare_video("abc", nil)}))
      assert {:error, :not_found} = ProviderLibrary.import(:cloudflare, "ABC", user)

      put_test_env(Mux, access_token_id: "id", access_token_secret: "secret", req_options: [plug: {Req.Test, Mux}])

      Req.Test.expect(Mux, 2, fn conn ->
        assert conn.request_path == "/video/v1/assets/ASSET-1"
        Req.Test.json(conn, %{"data" => %{"id" => "asset-1", "playback_ids" => [%{"id" => "pb", "policy" => "public"}]}})
      end)

      assert {:error, :not_found} = ProviderLibrary.import(:mux, "ASSET-1", user)
      assert Brando.Repo.aggregate(Brando.Videos.Video, :count) == 0
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
        "thumbnailFileName" => "thumbnail.jpg",
        "availableResolutions" => "360p,720p",
        "hasMP4Fallback" => true
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
      assert Brando.Videos.Playback.choices(video) == [:auto, :hls, :mp4_360, :mp4_720]
    end
  end

  describe "collections" do
    test "Vimeo lists its folders, and a folder's videos, searched within it" do
      Req.Test.expect(Vimeo, 2, fn conn ->
        assert conn.request_path == "/me/projects"
        assert %{"per_page" => "100", "sort" => "name", "direction" => "asc"} = conn.query_params
        assert conn.query_params["fields"] =~ "metadata.connections.videos.total"

        case conn.query_params["page"] do
          "1" ->
            Req.Test.json(conn, %{
              "paging" => %{"next" => "/me/projects?page=2"},
              "data" => [vimeo_folder("11", "Client A", 6), %{"uri" => "/users/1/albums/9", "name" => "Not a folder"}]
            })

          "2" ->
            Req.Test.json(conn, %{"paging" => %{"next" => nil}, "data" => [vimeo_folder("12", "", nil)]})
        end
      end)

      assert {:ok, [%{id: "11", name: "Client A", count: 6}, %{id: "12", name: "12", count: nil}]} =
               ProviderLibrary.collections(:vimeo)

      Req.Test.expect(Vimeo, fn conn ->
        assert conn.request_path == "/me/projects/11/videos"
        assert %{"page" => "1", "sort" => "date"} = conn.query_params
        refute Map.has_key?(conn.query_params, "query")

        video = Map.put(vimeo_video("1", "available"), "parent_folder", vimeo_folder("11", "Client A", 6))
        Req.Test.json(conn, %{"paging" => %{"next" => nil}, "data" => [video]})
      end)

      assert {:ok, %{items: [item], next: nil}} = ProviderLibrary.list(:vimeo, collection: "11")
      assert {item.collection_id, item.collection_name} == {"11", "Client A"}

      # The whole library: each video names its folder, or none
      Req.Test.expect(Vimeo, fn conn ->
        assert conn.request_path == "/me/videos"
        assert conn.query_params["fields"] =~ "parent_folder.uri,parent_folder.name"
        Req.Test.json(conn, %{"paging" => %{"next" => nil}, "data" => [vimeo_video("2", "available")]})
      end)

      assert {:ok, %{items: [%{collection_id: nil}]}} = ProviderLibrary.list(:vimeo, collection: "")
    end

    test "Vimeo searches a folder through the account's search, keeping the folder's videos" do
      in_folder = fn id -> Map.put(vimeo_video(id, "available"), "parent_folder", vimeo_folder("11", "Client A", 6)) end
      elsewhere = Map.put(vimeo_video("9", "available"), "parent_folder", vimeo_folder("12", "Client B", 1))

      # The folder's own listing takes no `query`: the account's search does,
      # and each video names its folder. A page with none of the folder's
      # reads the next, up to a bound.
      Req.Test.expect(Vimeo, 2, fn conn ->
        assert conn.request_path == "/me/videos"
        assert %{"query" => "harbour", "per_page" => "100"} = conn.query_params
        assert conn.query_params["fields"] =~ "parent_folder.uri"

        case conn.query_params["page"] do
          "1" ->
            Req.Test.json(conn, %{"paging" => %{"next" => "/me/videos?page=2"}, "data" => [elsewhere]})

          "2" ->
            Req.Test.json(conn, %{
              "paging" => %{"next" => "/me/videos?page=3"},
              "data" => [in_folder.("1"), vimeo_video("8", "available"), in_folder.("2")]
            })
        end
      end)

      assert {:ok, %{items: items, next: 3}} = ProviderLibrary.list(:vimeo, query: "harbour", collection: "11")
      assert Enum.map(items, &{&1.remote_id, &1.collection_id}) == [{"1", "11"}, {"2", "11"}]

      # Nothing in the folder within the bound: an empty page, and more to read
      Req.Test.expect(Vimeo, 3, fn conn ->
        page = String.to_integer(conn.query_params["page"])
        Req.Test.json(conn, %{"paging" => %{"next" => "/me/videos?page=#{page + 1}"}, "data" => [elsewhere]})
      end)

      assert {:ok, %{items: [], next: 6}} = ProviderLibrary.list(:vimeo, query: "harbour", collection: "11", cursor: 3)
    end

    test "Vimeo says a folder deleted since it was listed is gone" do
      Req.Test.expect(Vimeo, &send_resp(&1, 404, ~s({"error": "The requested folder could not be found"})))
      assert {:error, :collection_not_found} = ProviderLibrary.list(:vimeo, collection: "11")
    end

    test "Vimeo lists at most 1,000 folders, and says when there are more" do
      Req.Test.expect(Vimeo, 10, fn conn ->
        page = conn.query_params["page"]

        Req.Test.json(conn, %{
          "paging" => %{"next" => "/me/projects?page=x"},
          "data" => [vimeo_folder(page, "F#{page}", 1)]
        })
      end)

      assert {:ok, folders, :truncated} = ProviderLibrary.collections(:vimeo)
      assert length(folders) == 10
    end

    test "Bunny lists at most 1,000 collections, and says when there are more" do
      put_test_env(Bunny, api_key: "key", library_id: "77", req_options: [plug: {Req.Test, Bunny}])

      Req.Test.expect(Bunny, 10, fn conn ->
        page = String.to_integer(conn.query_params["page"])

        Req.Test.json(conn, %{
          "items" => [bunny_collection("c-#{page}", "C#{page}", 1)],
          "currentPage" => page,
          "itemsPerPage" => 100,
          "totalItems" => 1_500
        })
      end)

      assert {:ok, collections, :truncated} = ProviderLibrary.collections(:bunny)
      assert length(collections) == 10
    end

    test "Vimeo refuses a folder id that is not one, without asking" do
      assert {:error, :not_found} = ProviderLibrary.list(:vimeo, collection: "../videos/1")
    end

    test "Bunny lists its collections, and a collection's videos, searched within it" do
      put_test_env(Bunny, api_key: "key", library_id: "77", req_options: [plug: {Req.Test, Bunny}])

      Req.Test.expect(Bunny, 2, fn conn ->
        assert conn.request_path == "/library/77/collections"
        assert %{"itemsPerPage" => "100"} = conn.query_params

        {items, page} =
          case conn.query_params["page"] do
            "1" -> {[bunny_collection("c-2", "studio", 4), bunny_collection("c-1", "Harbour", 6)], 1}
            "2" -> {[bunny_collection("c-3", "Archive", 0)], 2}
          end

        Req.Test.json(conn, %{"items" => items, "currentPage" => page, "itemsPerPage" => 100, "totalItems" => 101})
      end)

      assert {:ok, collections} = ProviderLibrary.collections(:bunny)

      assert Enum.map(collections, &{&1.id, &1.name, &1.count}) == [
               {"c-3", "Archive", 0},
               {"c-1", "Harbour", 6},
               {"c-2", "studio", 4}
             ]

      Req.Test.expect(Bunny, fn conn ->
        assert conn.request_path == "/library/77/videos"
        assert %{"collection" => "c-1", "search" => "dawn", "page" => "1"} = conn.query_params

        Req.Test.json(conn, %{
          "items" => [
            %{"guid" => "v-1", "title" => "Dawn", "status" => 4, "collectionId" => "c-1"},
            %{"guid" => "v-2", "title" => "Dusk", "status" => 4, "collectionId" => ""}
          ],
          "currentPage" => 1,
          "itemsPerPage" => 24,
          "totalItems" => 2
        })
      end)

      assert {:ok, %{items: [one, two]}} = ProviderLibrary.list(:bunny, query: "dawn", collection: "c-1")
      assert {one.collection_id, two.collection_id} == {"c-1", nil}
    end

    test "a provider without them has none, and its items no collection" do
      put_test_env(Mux, access_token_id: "id", access_token_secret: "secret", req_options: [plug: {Req.Test, Mux}])

      assert ProviderLibrary.collections(:mux) == {:ok, []}
      assert {:error, {:unknown_strategy, :bunny}} = ProviderLibrary.collections(:bunny)

      Req.Test.expect(Mux, fn conn ->
        Req.Test.json(conn, %{
          "data" => [
            %{
              "id" => "ASSET-1",
              "status" => "ready",
              "playback_ids" => [%{"id" => "p", "policy" => "public"}],
              "created_at" => "1700000000"
            }
          ]
        })
      end)

      assert {:ok, %{items: [%{collection_id: nil}]}} = ProviderLibrary.list(:mux, collection: "c-1")
    end

    test "a provider error comes back as an error tuple" do
      Req.Test.expect(Vimeo, &send_resp(&1, 403, "forbidden"))
      assert {:error, {:http_error, 403, _body}} = ProviderLibrary.collections(:vimeo)
    end
  end

  defp vimeo_folder(id, name, count) do
    %{
      "uri" => "/users/1/projects/#{id}",
      "name" => name,
      "metadata" => %{"connections" => %{"videos" => %{"total" => count}}}
    }
  end

  defp bunny_collection(guid, name, count),
    do: %{"guid" => guid, "name" => name, "videoCount" => count, "videoLibraryId" => 77}

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
