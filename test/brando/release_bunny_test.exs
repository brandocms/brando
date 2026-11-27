defmodule Brando.ReleaseBunnyTest do
  # Run as over `rpc`: the application is running. Bunny's configuration is
  # the application's, read by every test.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import ExUnit.CaptureIO

  alias Brando.Factory
  alias Brando.Videos.Uploaders.Bunny
  alias Plug.Conn
  alias Req.Test, as: ReqTest

  setup do
    put_test_env(Bunny, api_key: "key", library_id: "133", req_options: [plug: {ReqTest, Bunny}])
    %{user: Factory.insert(:user)}
  end

  defp video(guid, user) do
    Factory.insert(:video,
      creator: user,
      type: :bunny,
      status: :ready,
      meta: %{
        "bunny" => %{
          "video_guid" => guid,
          "available_resolutions" => "360p",
          "has_mp4_fallback" => true,
          "thumbnail_url" => "thumbnail.jpg"
        }
      }
    )
  end

  defp stub_bunny do
    ReqTest.stub(Bunny, fn conn ->
      case conn.path_info do
        [_, _, _, "failing"] ->
          conn |> Conn.put_status(503) |> ReqTest.json(%{"Message" => "Down"})

        [_, _, _, guid] ->
          ReqTest.json(conn, %{
            "guid" => guid,
            "availableResolutions" => "360p",
            "hasMP4Fallback" => true,
            "thumbnailFileName" => if(guid == "renamed", do: "thumbnail_2bbb8a75.jpg", else: "thumbnail.jpg")
          })
      end
    end)
  end

  test "refresh_bunny_videos/0 runs Fetch details for each Bunny video, past one that fails, and is safe twice", %{
    user: user
  } do
    renamed = video("renamed", user)
    unchanged = video("unchanged", user)
    failing = video("failing", user)

    deleted =
      Factory.insert(:video,
        creator: user,
        type: :bunny,
        deleted_at: DateTime.utc_now(),
        meta: %{"bunny" => %{"video_guid" => "deleted"}}
      )

    _upload = Factory.insert(:video, creator: user, type: :upload)
    stub_bunny()

    failing_id = failing.id

    output =
      capture_io(fn ->
        assert %{refreshed: 1, unchanged: 1, failed: [{"public", ^failing_id}]} = Brando.Release.refresh_bunny_videos()
      end)

    assert output =~ "1 refreshed"
    assert output =~ "1 unchanged"
    assert output =~ "##{failing_id} in public"

    assert Brando.Repo.reload!(renamed).meta["bunny"]["thumbnail_url"] == "thumbnail_2bbb8a75.jpg"
    assert Brando.Repo.reload!(unchanged).updated_at == unchanged.updated_at
    assert Brando.Repo.reload!(deleted).meta == deleted.meta

    capture_io(fn ->
      assert %{refreshed: 0, unchanged: 2, failed: [{"public", ^failing_id}]} = Brando.Release.refresh_bunny_videos()
    end)
  end

  test "refresh_bunny_videos/0 asks Bunny once for a video, without retrying", %{user: user} do
    failing = video("failing", user)
    test = self()

    ReqTest.stub(Bunny, fn conn ->
      send(test, :asked)
      conn |> Conn.put_status(503) |> ReqTest.json(%{"Message" => "Down"})
    end)

    failing_id = failing.id

    capture_io(fn ->
      assert %{refreshed: 0, unchanged: 0, failed: [{"public", ^failing_id}]} = Brando.Release.refresh_bunny_videos()
    end)

    assert_received :asked
    refute_received :asked
  end

  test "refresh_bunny_videos/0 says so and does nothing without Bunny credentials", %{user: user} do
    video = video("renamed", user)
    put_test_env(Bunny, library_id: "133")
    ReqTest.stub(Bunny, fn _conn -> flunk("Bunny was asked") end)

    output = capture_io(fn -> assert Brando.Release.refresh_bunny_videos() == {:error, :not_configured} end)

    assert output =~ "Bunny is not configured"
    assert Brando.Repo.reload!(video).meta == video.meta
  end
end
