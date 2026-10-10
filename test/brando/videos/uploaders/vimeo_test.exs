defmodule Brando.Videos.Uploaders.VimeoTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.LiveViewTest, only: [render_component: 2]
  import Plug.Conn

  alias Brando.Factory
  alias Brando.Videos.Uploaders.Vimeo
  alias Brando.Worker.VimeoStatus

  @upload_link "https://us-files.tus.vimeo.com/files/vimeo-prod-src-tus-us/abc123"

  setup do
    previous = Application.get_env(:brando, Vimeo)

    Application.put_env(:brando, Vimeo,
      access_token: "vimeo-token",
      req_options: [plug: {Req.Test, Vimeo}]
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:brando, Vimeo, previous),
        else: Application.delete_env(:brando, Vimeo)
    end)
  end

  describe "initiate_upload/3" do
    test "creates a tus video without exposing the token, and schedules a status check" do
      test_pid = self()

      Req.Test.expect(Vimeo, fn conn ->
        {:ok, body, conn} = read_body(conn)

        send(test_pid, {
          :request,
          conn.method,
          conn.request_path,
          get_req_header(conn, "authorization"),
          get_req_header(conn, "accept"),
          Jason.decode!(body)
        })

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(created_payload("76979871")))
      end)

      user = Factory.insert(:random_user)

      config = %Brando.Type.VideoConfig{
        upload_strategy: :vimeo,
        meta: %{vimeo: %{"privacy_view" => "nobody", "folder_uri" => "/users/1/projects/2"}}
      }

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, result} =
                 Vimeo.initiate_upload("My clip.mp4", user,
                   config: config,
                   config_target: "video:Some.Schema:clip",
                   file_meta: %{name: "My clip.mp4", size: 12_345, type: "video/mp4"}
                 )

        assert result.upload_url == @upload_link
        assert result.tus_upload
        refute inspect(result) =~ "vimeo-token"

        assert result.video.type == :vimeo_account
        assert result.video.status == :uploading
        assert result.video.remote_id == "76979871"
        assert result.video.source_url == "https://vimeo.com/76979871/8272103f6e"
        assert result.video.config_target == "video:Some.Schema:clip"
        assert get_in(result.video.meta, ["vimeo", "video_id"]) == "76979871"
        assert get_in(result.video.meta, ["vimeo", "hash"]) == "8272103f6e"

        assert_enqueued(worker: VimeoStatus, args: %{"video_id" => result.video.id})
      end)

      assert_received {:request, "POST", "/me/videos", ["bearer vimeo-token"], [accept], body}
      assert accept =~ "version=3.4"

      assert body == %{
               "upload" => %{"approach" => "tus", "size" => "12345"},
               "name" => "My clip",
               "privacy" => %{"view" => "nobody"},
               "folder_uri" => "/users/1/projects/2"
             }
    end

    test "refuses an upload_link that is not on Vimeo" do
      Req.Test.expect(Vimeo, fn conn ->
        payload = put_in(created_payload("1"), ["upload", "upload_link"], "https://evil.example.com/files/1")
        Req.Test.json(conn, payload)
      end)

      user = Factory.insert(:random_user)

      assert {:error, :invalid_tus_response} =
               Vimeo.initiate_upload("clip.mp4", user,
                 config: %Brando.Type.VideoConfig{upload_strategy: :vimeo},
                 file_meta: %{name: "clip.mp4", size: 10, type: "video/mp4"}
               )
    end
  end

  describe "sync/1" do
    test "stores the stable HLS link, the largest thumbnail, size and duration once available" do
      video = insert_vimeo_video("555", :processing)

      Req.Test.expect(Vimeo, fn conn ->
        assert conn.request_path == "/videos/555"
        assert conn.query_params["fields"] =~ "files"
        Req.Test.json(conn, available_payload("555"))
      end)

      assert {:ok, updated} = Vimeo.sync(video)

      assert updated.status == :ready
      assert {updated.width, updated.height, updated.aspect_ratio} == {1920, 1080, "1920/1080"}
      assert updated.duration == "00:01:05"

      assert Vimeo.get_playback_url(updated) ==
               {:ok, "https://player.vimeo.com/external/555.m3u8?s=stable&oauth2_token_id=1"}

      assert Brando.Videos.Helpers.thumbnail_url(updated) == "https://i.vimeocdn.com/video/555-d_1920x1080"
    end

    test "maps Vimeo's failure states to errored and keeps a ready video ready while it re-transcodes" do
      failing = insert_vimeo_video("600", :processing)

      Req.Test.expect(Vimeo, fn conn ->
        Req.Test.json(conn, %{"uri" => "/videos/600", "status" => "transcoding_error"})
      end)

      assert {:ok, %{status: :errored}} = Vimeo.sync(failing)

      ready = insert_vimeo_video("601", :ready)

      Req.Test.expect(Vimeo, fn conn ->
        Req.Test.json(conn, %{
          "uri" => "/videos/601",
          "status" => "transcoding",
          "transcode" => %{"status" => "in_progress"}
        })
      end)

      assert {:ok, %{status: :ready}} = Vimeo.sync(ready)
    end

    test "reports a video Vimeo no longer has" do
      video = insert_vimeo_video("602", :processing)

      Req.Test.expect(Vimeo, &send_resp(&1, 404, ~s({"error": "not found"})))

      assert {:error, :not_found} = Vimeo.sync(video)
    end
  end

  describe "VimeoStatus worker" do
    test "snoozes while transcoding and stops once ready" do
      video = insert_vimeo_video("700", :processing)

      Req.Test.expect(Vimeo, fn conn ->
        Req.Test.json(conn, %{
          "uri" => "/videos/700",
          "status" => "transcoding",
          "transcode" => %{"status" => "in_progress"}
        })
      end)

      assert {:snooze, 15} = perform_job(VimeoStatus, %{"video_id" => video.id})

      Req.Test.expect(Vimeo, &Req.Test.json(&1, available_payload("700")))

      assert :ok = perform_job(VimeoStatus, %{"video_id" => video.id})
      assert Brando.Repo.get!(Brando.Videos.Video, video.id).status == :ready

      assert {:cancel, :not_pending} = perform_job(VimeoStatus, %{"video_id" => video.id})
    end

    test "marks the video errored when Vimeo has deleted it" do
      video = insert_vimeo_video("701", :processing)

      Req.Test.expect(Vimeo, &send_resp(&1, 404, ""))

      assert {:cancel, :gave_up} = perform_job(VimeoStatus, %{"video_id" => video.id})
      assert Brando.Repo.get!(Brando.Videos.Video, video.id).status == :errored
    end

    test "backs off as the upload ages" do
      assert Enum.map([0, 900, 7_200, 30_000], &VimeoStatus.interval/1) == [15, 60, 300, 900]
    end

    # The check queued when the upload began still waits when it completes,
    # however long the upload took: one poller per video.
    test "a completed upload joins the check still waiting from its start" do
      video = insert_vimeo_video("702", :uploading)

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, _} = %{"video_id" => video.id} |> VimeoStatus.new(schedule_in: 60) |> Oban.insert()
        age_jobs(VimeoStatus, 600)

        assert {:ok, %{status: :processing}} = Vimeo.complete_upload(video, %{})
        assert [_one] = all_enqueued(worker: VimeoStatus, args: %{"video_id" => video.id})
      end)
    end
  end

  test "completing the browser transfer moves the video to processing" do
    video = insert_vimeo_video("800", :uploading)

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, %{status: :processing}} = Brando.Videos.Uploader.complete_client_upload(video)
    end)
  end

  test "deletes the remote video, treating 404 as already gone" do
    test_pid = self()

    Req.Test.expect(Vimeo, 2, fn conn ->
      send(test_pid, {:delete, conn.method, conn.request_path})
      if conn.request_path == "/videos/900", do: send_resp(conn, 204, ""), else: send_resp(conn, 404, "")
    end)

    assert :ok = Vimeo.delete_remote(%Brando.Videos.Video{meta: %{"vimeo" => %{"video_id" => "900"}}})
    assert :ok = Vimeo.delete_remote(%Brando.Videos.Video{meta: %{"vimeo" => %{"video_id" => "901"}}})
    assert :ok = Vimeo.delete_remote(%Brando.Videos.Video{meta: %{}})

    assert_received {:delete, "DELETE", "/videos/900"}
    assert_received {:delete, "DELETE", "/videos/901"}
  end

  test "renders through <video> with the HLS link, and through Vimeo's player without one" do
    with_hls = %Brando.Videos.Video{
      type: :vimeo_account,
      status: :ready,
      meta: %{
        "vimeo" => %{
          "video_id" => "1",
          "hash" => "abcdef1234",
          "hls_url" => "https://player.vimeo.com/external/1.m3u8?s=x"
        }
      }
    }

    without_hls = put_in(with_hls.meta["vimeo"], Map.delete(with_hls.meta["vimeo"], "hls_url"))

    assert render(with_hls) =~ "player.vimeo.com/external/1.m3u8"
    assert render(without_hls) =~ ~s(src="https://player.vimeo.com/video/1?h=abcdef1234&amp;dnt=1")
  end

  defp render(video) do
    render_component(&Brando.HTML.Video.video/1, video: video, opts: [])
  end

  defp age_jobs(worker, seconds) do
    import Ecto.Query, only: [from: 2]
    inserted_at = DateTime.add(DateTime.utc_now(), -seconds)
    Brando.Repo.update_all(from(j in Oban.Job, where: j.worker == ^inspect(worker)), set: [inserted_at: inserted_at])
  end

  defp insert_vimeo_video(video_id, status) do
    user = Factory.insert(:random_user)

    Factory.insert(:video,
      creator: user,
      type: :vimeo_account,
      status: status,
      remote_id: video_id,
      meta: %{"provider" => "vimeo", "vimeo" => %{"video_id" => video_id}}
    )
  end

  defp created_payload(video_id) do
    %{
      "uri" => "/videos/#{video_id}",
      "link" => "https://vimeo.com/#{video_id}/8272103f6e",
      "player_embed_url" => "https://player.vimeo.com/video/#{video_id}?h=8272103f6e",
      "status" => "uploading",
      "upload" => %{"approach" => "tus", "status" => "in_progress", "upload_link" => @upload_link}
    }
  end

  defp available_payload(video_id) do
    %{
      "uri" => "/videos/#{video_id}",
      "link" => "https://vimeo.com/#{video_id}",
      "player_embed_url" => "https://player.vimeo.com/video/#{video_id}",
      "status" => "available",
      "upload" => %{"status" => "complete"},
      "transcode" => %{"status" => "complete"},
      "width" => 1920,
      "height" => 1080,
      "duration" => 65,
      "pictures" => %{
        "base_link" => "https://i.vimeocdn.com/video/#{video_id}-d",
        "sizes" => [
          %{"width" => 640, "link" => "https://i.vimeocdn.com/video/#{video_id}-d_640x360"},
          %{"width" => 1920, "link" => "https://i.vimeocdn.com/video/#{video_id}-d_1920x1080"}
        ]
      },
      "files" => [
        %{"quality" => "hd", "rendition" => "1080p", "link" => "https://player.vimeo.com/progressive_redirect/x"},
        %{
          "quality" => "hls",
          "rendition" => "adaptive",
          "link" => "https://player.vimeo.com/external/#{video_id}.m3u8?s=stable&oauth2_token_id=1"
        }
      ]
    }
  end
end
