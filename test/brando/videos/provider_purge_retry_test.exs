defmodule Brando.Videos.ProviderPurgeRetryTest do
  # A provider error while a deleted video is purged, or deleted with
  # `delete_remote_on: :on_delete`: a transient one (a timeout, a connection
  # error, a 5xx or a 429) is tried again, and any other is not.
  use Brando.ConnCase, async: false

  import Brando.Test.Support, only: [put_test_env: 2]
  import ExUnit.CaptureLog
  import Plug.Conn

  alias Brando.Factory
  alias Brando.Repo
  alias Brando.Videos.Uploader
  alias Brando.Videos.Uploaders.Bunny
  alias Brando.Videos.Uploaders.Cloudflare
  alias Brando.Videos.Uploaders.Mux
  alias Brando.Videos.Uploaders.Vimeo
  alias Brando.Videos.Video
  alias Brando.Worker.VideoRemoteDelete

  @providers [
    mux: {Mux, :mux, %{"mux" => %{"asset_id" => "asset-1"}}},
    bunny: {Bunny, :bunny, %{"bunny" => %{"video_guid" => "guid-1"}}},
    cloudflare: {Cloudflare, :cloudflare, %{"cloudflare" => %{"uid" => "uid1"}}},
    vimeo: {Vimeo, :vimeo_account, %{"vimeo" => %{"video_id" => "900"}}}
  ]

  @transient [
    {"a 503", {:status, 503}},
    {"a 429", {:status, 429}},
    {"a timeout", {:transport, :timeout}},
    {"a refused connection", {:transport, :econnrefused}}
  ]

  setup do
    put_test_env(:tenancy_mode, :none)
    Logger.put_module_level(Uploader, :info)
    Logger.put_module_level(Brando.SoftDelete.Query, :info)

    on_exit(fn ->
      Logger.delete_module_level(Uploader)
      Logger.delete_module_level(Brando.SoftDelete.Query)
    end)

    :ok
  end

  for {provider, {module, type, meta}} <- @providers do
    @module module
    @type_ type
    @meta meta

    describe "a purge, #{provider}" do
      for {label, failure} <- @transient do
        @failure failure

        test "keeps the row on #{label}, and a later purge deletes the video at the provider" do
          configure(@module, :on_purge)
          video = @module |> insert_video(@type_, @meta) |> expire()

          answer(@module, @failure)
          log = capture_log([level: :info], fn -> assert purge_videos() == 0 end)

          assert_received {:provider, "DELETE", _path}
          assert Repo.get!(Video, video.id).deleted_at
          assert log =~ "Video #{video.id} kept for the next purge"

          answer(@module, :ok)
          assert purge_videos() == 1
          assert_received {:provider, "DELETE", _path}
          refute Repo.get(Video, video.id)
        end
      end

      test "deletes the row on a permanent error, and does not ask the provider again" do
        configure(@module, :on_purge)
        video = @module |> insert_video(@type_, @meta) |> expire()

        answer(@module, {:status, 403})
        capture_log(fn -> assert purge_videos() == 1 end)

        assert_received {:provider, "DELETE", _path}
        refute Repo.get(Video, video.id)

        answer(@module, :ok)
        assert purge_videos() == 0
        refute_received {:provider, "DELETE", _path}
      end
    end

    describe "a delete with delete_remote_on: :on_delete, #{provider}" do
      test "is tried again after a transient error, until the provider deletes the video" do
        configure(@module, :on_delete)
        user = Factory.insert(:random_user, role: :superuser)
        video = insert_video(@module, @type_, @meta)
        answer(@module, {:status, 503})

        Oban.Testing.with_testing_mode(:manual, fn ->
          capture_log(fn -> assert {:ok, _} = Brando.Videos.delete_video(video.id, user) end)
          assert_received {:provider, "DELETE", _path}
          assert_enqueued(worker: VideoRemoteDelete, args: %{"video_id" => video.id})

          # Still unavailable: the job fails, so Oban tries it again.
          capture_log(fn -> assert {:error, _} = perform_job(VideoRemoteDelete, %{"video_id" => video.id}) end)
          assert_received {:provider, "DELETE", _path}

          answer(@module, :ok)
          assert :ok = perform_job(VideoRemoteDelete, %{"video_id" => video.id})
          assert_received {:provider, "DELETE", _path}
        end)
      end

      test "is not tried again after a permanent error" do
        configure(@module, :on_delete)
        user = Factory.insert(:random_user, role: :superuser)
        video = insert_video(@module, @type_, @meta)
        answer(@module, {:status, 403})

        Oban.Testing.with_testing_mode(:manual, fn ->
          capture_log(fn -> assert {:ok, _} = Brando.Videos.delete_video(video.id, user) end)
          assert_received {:provider, "DELETE", _path}
          refute_enqueued(worker: VideoRemoteDelete)
        end)
      end
    end
  end

  describe "a purge with a provider that cannot be reached" do
    # Each call to a provider that hangs waits out its timeout, and the
    # purger has 30 seconds for every schema and environment.
    test "asks it once, keeps its other rows for the next run, and purges the other providers' rows" do
      configure(Mux, :on_purge)
      configure(Bunny, :on_purge)

      mux_videos =
        for id <- ["asset-1", "asset-2"], do: Mux |> insert_video(:mux, %{"mux" => %{"asset_id" => id}}) |> expire()

      bunny_video = Bunny |> insert_video(:bunny, %{"bunny" => %{"video_guid" => "guid-1"}}) |> expire()

      answer(Mux, {:transport, :timeout})
      answer(Bunny, :ok)
      log = capture_log([level: :info], fn -> assert purge_videos() == 1 end)

      assert_received {:provider, "DELETE", "/video/v1/assets/" <> _id}
      refute_received {:provider, "DELETE", "/video/v1/assets/" <> _id}
      assert_received {:provider, "DELETE", "/library/1/videos/guid-1"}
      refute Repo.get(Video, bunny_video.id)
      for video <- mux_videos, do: assert(Repo.get!(Video, video.id).deleted_at)
      assert log =~ "1 more mux video kept for the next purge"

      answer(Mux, :ok)
      assert purge_videos() == 2
      for video <- mux_videos, do: refute(Repo.get(Video, video.id))
    end
  end

  describe "a purge with a provider that answers with an error after a long wait" do
    # A gateway's 504, after it waited on the provider behind it: the answer
    # is a status, but it took as long as a timeout.
    test "asks it once, and keeps its other rows for the next run" do
      put_test_env(Brando.SoftDelete.Query, slow_failure_ms: 50)
      configure(Mux, :on_purge)

      videos =
        for id <- ["asset-1", "asset-2"], do: Mux |> insert_video(:mux, %{"mux" => %{"asset_id" => id}}) |> expire()

      me = self()

      Req.Test.stub(Mux, fn conn ->
        send(me, {:provider, conn.method, conn.request_path})
        Process.sleep(60)
        send_resp(conn, 504, ~s({"error":"x"}))
      end)

      log = capture_log([level: :info], fn -> assert purge_videos() == 0 end)

      assert_received {:provider, "DELETE", "/video/v1/assets/" <> _id}
      refute_received {:provider, "DELETE", "/video/v1/assets/" <> _id}
      for video <- videos, do: assert(Repo.get!(Video, video.id).deleted_at)
      assert log =~ "1 more mux video kept for the next purge"
    end
  end

  describe "a purge with a provider that answers with an error" do
    # An error status comes back at once, and may be one video's alone, such
    # as an asset the provider cannot delete: its other videos are still asked.
    test "asks it about each of its videos, and purges the ones it deletes" do
      configure(Mux, :on_purge)

      [failing, busy, deleted] =
        for id <- ["asset-1", "asset-2", "asset-3"],
            do: Mux |> insert_video(:mux, %{"mux" => %{"asset_id" => id}}) |> expire()

      me = self()

      Req.Test.stub(Mux, fn conn ->
        send(me, {:provider, conn.method, conn.request_path})

        case conn.request_path do
          "/video/v1/assets/asset-1" -> send_resp(conn, 500, ~s({"error":"x"}))
          "/video/v1/assets/asset-2" -> send_resp(conn, 429, ~s({"error":"x"}))
          "/video/v1/assets/asset-3" -> send_resp(conn, 204, "")
        end
      end)

      log = capture_log([level: :info], fn -> assert purge_videos() == 1 end)

      for id <- ["asset-1", "asset-2", "asset-3"], do: assert_received({:provider, "DELETE", "/video/v1/assets/" <> ^id})
      assert Repo.get!(Video, failing.id).deleted_at
      assert Repo.get!(Video, busy.id).deleted_at
      refute Repo.get(Video, deleted.id)
      refute log =~ "without asking the provider"
    end
  end

  describe "the delete retried after delete_remote_on: :on_delete" do
    setup do
      configure(Mux, :on_delete)
      answer(Mux, :ok)
      :ok
    end

    test "leaves a record restored meanwhile, and its video" do
      video = insert_video(Mux, :mux, %{"mux" => %{"asset_id" => "asset-1"}})
      assert {:cancel, _} = perform_job(VideoRemoteDelete, %{"video_id" => video.id})
      refute_received {:provider, "DELETE", _path}
    end

    test "stops once the record is purged" do
      assert {:cancel, _} = perform_job(VideoRemoteDelete, %{"video_id" => 0})
      refute_received {:provider, "DELETE", _path}
    end

    test "leaves a video that another live record of the environment plays" do
      deleted = Mux |> insert_video(:mux, %{"mux" => %{"asset_id" => "asset-1"}}) |> soft_delete()
      _imported = insert_video(Mux, :mux, %{"mux" => %{"asset_id" => "asset-1"}, "imported" => true})

      capture_log([level: :info], fn -> assert :ok = perform_job(VideoRemoteDelete, %{"video_id" => deleted.id}) end)
      refute_received {:provider, "DELETE", _path}
    end
  end

  defp configure(Mux, timing),
    do:
      put_test_env(Mux,
        access_token_id: "id",
        access_token_secret: "secret",
        delete_remote_on: timing,
        req_options: req(Mux)
      )

  defp configure(Bunny, timing),
    do:
      put_test_env(Bunny,
        api_key: "key",
        library_id: "1",
        cdn_hostname: "cdn.example",
        delete_remote_on: timing,
        req_options: req(Bunny)
      )

  defp configure(Cloudflare, timing),
    do:
      put_test_env(Cloudflare,
        account_id: "acc",
        api_token: "tok",
        delete_remote_on: timing,
        req_options: req(Cloudflare)
      )

  defp configure(Vimeo, timing),
    do: put_test_env(Vimeo, access_token: "tok", delete_remote_on: timing, req_options: req(Vimeo))

  # No retries by Req itself: each provider call is one request.
  defp req(module), do: [plug: {Req.Test, module}, retry: false]

  defp answer(module, outcome) do
    me = self()

    Req.Test.stub(module, fn conn ->
      send(me, {:provider, conn.method, conn.request_path})

      case outcome do
        :ok -> send_resp(conn, 204, "")
        {:status, status} -> conn |> put_resp_content_type("application/json") |> send_resp(status, ~s({"error":"x"}))
        {:transport, reason} -> Req.Test.transport_error(conn, reason)
      end
    end)
  end

  defp insert_video(_module, type, meta), do: Repo.insert!(%Video{type: type, title: "Video", status: :ready, meta: meta})

  defp soft_delete(video), do: video |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()

  defp expire(video) do
    video |> Ecto.Changeset.change(deleted_at: DateTime.add(DateTime.utc_now(:second), -31, :day)) |> Repo.update!()
  end

  # Purges the expired records, and returns how many videos it purged.
  defp purge_videos do
    Brando.SoftDelete.Query.list_soft_delete_schemas()
    |> Enum.zip(Brando.SoftDelete.Query.clean_up_soft_deletions())
    |> Map.new()
    |> Map.fetch!(Video)
    |> elem(0)
  end
end
