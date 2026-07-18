defmodule Brando.Videos.Uploaders.CloudflareTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Plug.Conn

  alias Brando.Factory
  alias Brando.Videos.Uploaders.Cloudflare

  setup do
    previous = Application.get_env(:brando, Cloudflare)

    Application.put_env(:brando, Cloudflare,
      account_id: "account-id",
      api_token: "api-token",
      webhook_secret: "webhook-secret",
      req_options: [plug: {Req.Test, Cloudflare}]
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:brando, Cloudflare, previous),
        else: Application.delete_env(:brando, Cloudflare)
    end)
  end

  test "provisions a direct-user tus resource without exposing the API token" do
    test_pid = self()
    uid = "6b9e68b07dfee8cc2d116e4c51d6a957"
    upload_url = "https://upload.videodelivery.net/tus/#{uid}"

    Req.Test.expect(Cloudflare, fn conn ->
      send(test_pid, {
        :request,
        conn.method,
        conn.request_path,
        conn.query_string,
        get_req_header(conn, "authorization"),
        get_req_header(conn, "tus-resumable"),
        get_req_header(conn, "upload-length"),
        get_req_header(conn, "upload-metadata")
      })

      conn
      |> put_resp_header("location", upload_url)
      |> put_resp_header("stream-media-id", uid)
      |> send_resp(201, "")
    end)

    user = Factory.insert(:random_user)

    config = %Brando.Type.VideoConfig{
      upload_strategy: :cloudflare,
      meta: %{cloudflare: %{"max_duration_seconds" => 900}}
    }

    assert {:ok, result} =
             Cloudflare.initiate_upload("My clip.mp4", user,
               config: config,
               config_target: "video:Some.Schema:clip",
               file_meta: %{name: "My clip.mp4", size: 12_345, type: "video/mp4"}
             )

    assert result.upload_url == upload_url
    assert result.video.type == :cloudflare
    assert result.video.status == :uploading
    assert result.video.remote_id == uid
    assert get_in(result.video.meta, ["cloudflare", "uid"]) == uid

    assert_received {:request, "POST", "/client/v4/accounts/account-id/stream", "direct_user=true", ["Bearer api-token"],
                     ["1.0.0"], ["12345"], [metadata]}

    assert decode_metadata(metadata) == %{
             "maxDurationSeconds" => "900",
             "name" => "My clip.mp4"
           }
  end

  test "maps a ready webhook to playback, dimensions, duration, and ready state" do
    user = Factory.insert(:random_user)
    uid = "cf-ready-id"

    video =
      Factory.insert(:video,
        creator: user,
        type: :cloudflare,
        status: :processing,
        meta: %{"provider" => "cloudflare", "cloudflare" => %{"uid" => uid}}
      )

    payload = ready_payload(uid)

    assert {:ok, updated} = Cloudflare.handle_webhook(payload)
    assert updated.id == video.id
    assert updated.status == :ready
    assert updated.width == 1920
    assert updated.height == 1080
    assert updated.aspect_ratio == "1920/1080"
    assert updated.duration == "00:00:13"
    assert Cloudflare.get_playback_url(updated) == {:ok, get_in(payload, ["playback", "hls"])}
    assert Brando.Videos.Helpers.thumbnail_url(updated) == payload["thumbnail"]
  end

  test "does not let a stale terminal webhook regress ready or errored records" do
    user = Factory.insert(:random_user)

    _ready =
      Factory.insert(:video,
        creator: user,
        type: :cloudflare,
        status: :ready,
        meta: %{"provider" => "cloudflare", "cloudflare" => %{"uid" => "ready-id"}}
      )

    _errored =
      Factory.insert(:video,
        creator: user,
        type: :cloudflare,
        status: :errored,
        meta: %{"provider" => "cloudflare", "cloudflare" => %{"uid" => "error-id"}}
      )

    error_payload = %{
      "uid" => "ready-id",
      "readyToStream" => false,
      "status" => %{"state" => "error", "errorReasonCode" => "ERR_MALFORMED_VIDEO"}
    }

    assert {:ok, unchanged_ready} = Cloudflare.handle_webhook(error_payload)
    assert unchanged_ready.status == :ready

    assert {:ok, unchanged_error} = Cloudflare.handle_webhook(ready_payload("error-id"))
    assert unchanged_error.status == :errored
  end

  test "rejects signed playback at the playback boundary" do
    video = %Brando.Videos.Video{
      type: :cloudflare,
      status: :ready,
      meta: %{
        "cloudflare" => %{
          "require_signed_urls" => true,
          "playback_hls" => "https://example.com/signed.m3u8"
        }
      }
    }

    assert {:error, :signed_playback_not_supported} = Cloudflare.get_playback_url(video)
    assert Brando.Videos.Helpers.thumbnail_url(video) == nil
  end

  test "deletes the remote Stream video through the account API" do
    test_pid = self()

    Req.Test.expect(Cloudflare, fn conn ->
      send(test_pid, {:delete_request, conn.method, conn.request_path})
      send_resp(conn, 204, "")
    end)

    video = %Brando.Videos.Video{
      type: :cloudflare,
      meta: %{"cloudflare" => %{"uid" => "remote-video-id"}}
    }

    assert :ok = Cloudflare.delete_remote(video)

    assert_received {:delete_request, "DELETE", "/client/v4/accounts/account-id/stream/remote-video-id"}
  end

  defp ready_payload(uid) do
    %{
      "uid" => uid,
      "readyToStream" => true,
      "status" => %{"state" => "ready", "pctComplete" => "100.000000"},
      "duration" => 12.6,
      "input" => %{"width" => 1920, "height" => 1080},
      "thumbnail" => "https://customer.example.com/#{uid}/thumbnails/thumbnail.jpg",
      "requireSignedURLs" => false,
      "playback" => %{
        "hls" => "https://customer.example.com/#{uid}/manifest/video.m3u8",
        "dash" => "https://customer.example.com/#{uid}/manifest/video.mpd"
      }
    }
  end

  defp decode_metadata(metadata) do
    metadata
    |> String.split(",")
    |> Map.new(fn pair ->
      [key, encoded] = String.split(pair, " ", parts: 2)
      {key, Base.decode64!(encoded)}
    end)
  end
end
