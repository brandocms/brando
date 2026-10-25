defmodule Brando.Videos.Uploaders.BunnyTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Videos.Uploaders.Bunny

  setup do
    previous = Application.get_env(:brando, Bunny)
    Application.put_env(:brando, Bunny, library_id: "133")

    on_exit(fn ->
      if previous,
        do: Application.put_env(:brando, Bunny, previous),
        else: Application.delete_env(:brando, Bunny)
    end)
  end

  test "late processing webhooks cannot regress a ready video" do
    user = Factory.insert(:user)
    guid = Ecto.UUID.generate()

    video =
      Factory.insert(:video,
        creator: user,
        type: :bunny,
        status: :ready,
        meta: %{"provider" => "bunny", "bunny" => %{"video_guid" => guid}}
      )

    assert {:ok, updated_video} =
             Bunny.handle_webhook(%{"VideoLibraryId" => 133, "VideoGuid" => guid, "Status" => 2})

    assert updated_video.id == video.id
    assert updated_video.status == :ready
    assert Brando.Repo.reload!(video).status == :ready
  end

  describe "renditions" do
    setup do
      put_test_env(Bunny, api_key: "key", library_id: "133", req_options: [plug: {Req.Test, Bunny}])
      :ok
    end

    defp bunny_details(guid, overrides) do
      Map.merge(
        %{
          "guid" => guid,
          "videoLibraryId" => 133,
          "status" => 3,
          "width" => 1080,
          "height" => 1350,
          "availableResolutions" => "360p,480p,720p,1080p",
          "hasMP4Fallback" => true
        },
        overrides
      )
    end

    test "a finished video stores which MP4s Bunny made" do
      user = Factory.insert(:user)
      guid = Ecto.UUID.generate()

      Factory.insert(:video,
        creator: user,
        type: :bunny,
        status: :processing,
        meta: %{"provider" => "bunny", "bunny" => %{"video_guid" => guid}}
      )

      Req.Test.expect(Bunny, &Req.Test.json(&1, bunny_details(guid, %{})))
      assert {:ok, video} = Bunny.handle_webhook(%{"VideoLibraryId" => 133, "VideoGuid" => guid, "Status" => 3})
      assert video.meta["bunny"]["has_mp4_fallback"] == true
      assert Brando.Videos.Playback.choices(video) == [:auto, :hls, :mp4_360, :mp4_480, :mp4_720, :mp4_1080]

      Req.Test.expect(Bunny, &Req.Test.json(&1, bunny_details(guid, %{"hasMP4Fallback" => false})))
      assert {:ok, video} = Bunny.handle_webhook(%{"VideoLibraryId" => 133, "VideoGuid" => guid, "Status" => 3})
      assert video.meta["bunny"]["has_mp4_fallback"] == false
      assert Brando.Videos.Playback.choices(video) == [:auto, :hls]
    end

    # Stored before Brando kept the flag: the sweep behind Fetch details looks
    # it up, and changes nothing else an editor may have set
    test "a ready video without the flag is looked up by Fetch details, keeping its own settings" do
      user = Factory.insert(:user)
      guid = Ecto.UUID.generate()

      video =
        Factory.insert(:video,
          creator: user,
          type: :bunny,
          status: :ready,
          aspect_ratio: "1/1",
          meta: %{"provider" => "bunny", "bunny" => %{"video_guid" => guid, "length" => 12}}
        )

      known =
        Factory.insert(:video,
          creator: user,
          type: :bunny,
          status: :ready,
          meta: %{"bunny" => %{"video_guid" => Ecto.UUID.generate(), "has_mp4_fallback" => false}}
        )

      ids = Brando.Videos.list_video_ids_missing_metadata()
      assert video.id in ids
      refute known.id in ids

      Req.Test.expect(Bunny, fn conn ->
        assert conn.request_path == "/library/133/videos/#{guid}"
        Req.Test.json(conn, bunny_details(guid, %{"availableResolutions" => "360p,720p"}))
      end)

      assert {:ok, refreshed} = Brando.Videos.fetch_metadata(video, user)

      assert refreshed.meta["bunny"] == %{
               "video_guid" => guid,
               "length" => 12,
               "available_resolutions" => "360p,720p",
               "has_mp4_fallback" => true
             }

      assert refreshed.aspect_ratio == "1/1"
      refute refreshed.id in Brando.Videos.list_video_ids_missing_metadata()
    end

    test "a video Bunny no longer has gets no MP4s, and isn't looked up again" do
      user = Factory.insert(:user)
      guid = Ecto.UUID.generate()

      video =
        Factory.insert(:video,
          creator: user,
          type: :bunny,
          status: :ready,
          meta: %{"bunny" => %{"video_guid" => guid}}
        )

      Req.Test.expect(Bunny, fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"Message" => "Not Found"})
      end)

      assert {:ok, refreshed} = Brando.Videos.fetch_metadata(video, user)
      assert refreshed.meta["bunny"]["has_mp4_fallback"] == false
      refute video.id in Brando.Videos.list_video_ids_missing_metadata()
    end

    test "Fetch details leaves Bunny videos alone without Bunny credentials" do
      put_test_env(Bunny, library_id: "133")
      user = Factory.insert(:user)

      video =
        Factory.insert(:video,
          creator: user,
          type: :bunny,
          status: :ready,
          meta: %{"bunny" => %{"video_guid" => Ecto.UUID.generate()}}
        )

      refute video.id in Brando.Videos.list_video_ids_missing_metadata()
      assert Brando.Videos.fetch_metadata(video, user) == {:error, :unsupported}
    end
  end

  test "terminal errors ignore later stale provider status" do
    user = Factory.insert(:user)
    guid = Ecto.UUID.generate()

    video =
      Factory.insert(:video,
        creator: user,
        type: :bunny,
        status: :errored,
        meta: %{"provider" => "bunny", "bunny" => %{"video_guid" => guid}}
      )

    assert {:ok, updated_video} =
             Bunny.handle_webhook(%{"VideoLibraryId" => 133, "VideoGuid" => guid, "Status" => 3})

    assert updated_video.status == :errored
    assert Brando.Repo.reload!(video).status == :errored
  end
end
